//! Build-time scanner for extension class files.
//!
//! Writes a generated namespace module of file-stem imports for files matching
//! `pub const Extends =`. Metadata is cached under the build cache root.

const scanner_version: u32 = 0x000003;
const class_pattern = "pub const Extends =";
const glob_pattern = "**/*.zig";

const max_source_bytes = 64 * 1024 * 1024;
const manifest_name = "manifest.bin";
const timestamp_name = "timestamp";
const manifest_magic: u32 = 0x31534643; // "CFS1"

const Entry = struct {
    size: u64,
    mtime_ns: i64,
    inode: u64,
    flags: bitpack struct(u8) {
        /// False when the mtime was too recent to trust (it could still change
        /// within the same filesystem timestamp tick). Untrusted entries are
        /// always rescanned.
        trusted: bool = false,
        matched: bool = false,
        padding0: u6 = 0,
    },
};

const Record = struct {
    path: []const u8,
    entry: Entry,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) {
        std.log.err(
            "usage: class_files_scan_and_gen <cache_root> <scan_dir> <output_module> [ignore...]",
            .{},
        );
        return error.InsufficientArgs;
    }

    const cache_root = args[1];
    const scan_path = args[2];
    const output_module_path = args[3];

    const extra_ignore = try std.mem.join(arena, "\n", if (args.len > 4) args[4..] else &.{});

    // Everything that changes the answer goes into the config hash; if it
    // differs from the manifest's, the manifest is discarded.
    var h = std.hash.Wyhash.init(0);
    h.update(std.mem.asBytes(&scanner_version));
    h.update(class_pattern);
    h.update("\x00");
    h.update(scan_path);
    h.update("\x00");
    h.update(glob_pattern);
    h.update("\x00");
    h.update(extra_ignore);
    const config_hash = h.final();

    const scan_root = if (std.fs.path.isAbsolute(scan_path))
        Io.Dir.openDirAbsolute(io, scan_path, .{}) catch |err| {
            std.log.err("cannot open scan root '{s}': {t}", .{ scan_path, err });
            return err;
        }
    else
        Io.Dir.cwd().openDir(io, scan_path, .{}) catch |err| {
            std.log.err("cannot open scan root '{s}': {t}", .{ scan_path, err });
            return err;
        };
    var scan_root_dir = scan_root;
    scan_root_dir.close(io);

    const cache_key = try std.fmt.allocPrint(arena, "{x}", .{config_hash});
    const scan_cache_dir = try std.fs.path.join(
        arena,
        &.{ cache_root, "class_files_scanner", cache_key },
    );
    const manifest_path = try std.fs.path.join(arena, &.{ scan_cache_dir, manifest_name });
    const timestamp_path = try std.fs.path.join(arena, &.{ scan_cache_dir, timestamp_name });

    const cwd = Io.Dir.cwd();
    {
        var d = try cwd.createDirPathOpen(io, scan_cache_dir, .{});
        d.close(io);
    }

    const fs_now_ns = try filesystemNow(io, timestamp_path);
    const old = loadManifest(arena, io, manifest_path, config_hash);

    var results = try zlob.walk.collect(gpa, scan_path, .{
        .threads = 1,
        .sort = true,
        .report_dirs = false,
        .respect_git = false,
        .abort_on_error = true,
        .meta = .{ .size = true, .mtime = true, .inode = true },
        .pattern = glob_pattern,
        .extra_ignore = extra_ignore,
    });
    defer results.deinit();

    var records: std.ArrayList(Record) = .empty;
    defer records.deinit(gpa);
    var matches: std.ArrayList([]const u8) = .empty;
    defer matches.deinit(gpa);
    try records.ensureTotalCapacity(gpa, results.entries.len);

    var reused: usize = 0;
    var rescanned: usize = 0;
    var dirty = false;

    for (results.entries) |*entry| {
        if (entry.kind != .file) continue;
        const rel = entry.relativePath();

        var size: u64 = 0;
        var mtime_ns: i64 = 0;
        var inode: u64 = 0;
        var have_meta = false;
        if (entry.meta) |m| {
            if (m.valid.size and m.valid.mtime) {
                have_meta = true;
                size = m.size;
                mtime_ns = m.mtime_ns;
                inode = if (m.valid.inode) m.inode else 0;
            }
        }

        const reuse: ?bool = blk: {
            if (!have_meta) break :blk null;
            const o = findOld(old, rel) orelse break :blk null;
            if (!o.entry.flags.trusted) break :blk null;
            if (o.entry.size != size or
                o.entry.mtime_ns != mtime_ns or
                o.entry.inode != inode) break :blk null;
            break :blk o.entry.flags.matched;
        };

        const new_entry: Entry = blk: {
            if (reuse) |matched| {
                reused += 1;
                break :blk .{
                    .size = size,
                    .mtime_ns = mtime_ns,
                    .inode = inode,
                    .flags = .{ .trusted = true, .matched = matched },
                };
            } else {
                rescanned += 1;
                dirty = true;
                const scanned = try scanFile(gpa, io, entry.path);
                break :blk .{
                    .size = size,
                    .mtime_ns = mtime_ns,
                    .inode = inode,
                    .flags = .{
                        .trusted = have_meta and mtime_ns < fs_now_ns,
                        .matched = scanned,
                    },
                };
            }
        };

        records.appendAssumeCapacity(.{ .path = rel, .entry = new_entry });
        if (new_entry.flags.matched) try matches.append(gpa, rel);
    }

    // Removed files shrink the set without causing any rescan.
    if (old.len != records.items.len) dirty = true;
    if (dirty) try writeManifest(gpa, io, manifest_path, config_hash, records.items);

    try writeOutputModule(gpa, arena, io, scan_path, output_module_path, matches.items);

    std.log.debug("class scan: {d} files, {d} reused, {d} rescanned, {d} matched", .{
        records.items.len, reused, rescanned, matches.items.len,
    });
}

/// Reads `path` and searches for the pattern. Read errors abort the scan.
fn scanFile(gpa: Allocator, io: Io, path: []const u8) !bool {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_source_bytes));
    defer gpa.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), class_pattern)) return true;
    }
    return false;
}

/// Same trick std.Build.Cache uses: touch a file and read back its mtime to
/// learn what "now" is according to the filesystem's own clock and
/// granularity. Files with an mtime at or after this can't be trusted yet.
fn filesystemNow(io: Io, timestamp_path: []const u8) !i64 {
    var file = try Io.Dir.cwd().createFile(io, timestamp_path, .{
        .read = true,
        .truncate = true,
    });
    defer file.close(io);
    const st = try file.stat(io);
    return @intCast(st.mtime.toNanoseconds());
}

// Manifest
// Layout (little endian):
//   u32 magic | u64 config_hash | u32 count
//   count x { u32 path_len | path | u64 size | i64 mtime_ns | u64 inode | u8 flags }
//   u64 wyhash of everything above
// flags: bit0 = trusted, bit1 = matched

const OldRecord = struct {
    path: []const u8,
    entry: Entry,

    fn lessThan(_: void, a: OldRecord, b: OldRecord) bool {
        return std.mem.order(u8, a.path, b.path) == .lt;
    }
};

fn loadManifest(arena: Allocator, io: Io, path: []const u8, config_hash: u64) []const OldRecord {
    const bytes = Io.Dir.cwd().readFileAlloc(
        io,
        path,
        arena,
        .limited(256 * 1024 * 1024),
    ) catch return &.{};
    const recs = parseManifest(arena, bytes, config_hash) catch return &.{};
    std.mem.sortUnstable(OldRecord, recs, {}, OldRecord.lessThan);
    return recs;
}

fn parseManifest(arena: Allocator, bytes: []const u8, config_hash: u64) ![]OldRecord {
    if (bytes.len < 8) return error.Corrupt;
    const body = bytes[0 .. bytes.len - 8];
    const stored = std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little);
    if (stored != std.hash.Wyhash.hash(0, body)) return error.Corrupt;

    var c: Cursor = .{ .bytes = body };
    if ((try c.int(u32)) != manifest_magic) return error.Corrupt;
    if ((try c.int(u64)) != config_hash) return error.ConfigChanged;
    const count = try c.int(u32);

    const recs = try arena.alloc(OldRecord, count);
    for (recs) |*r| {
        const path_len = try c.int(u32);
        const path = try c.take(path_len);
        const size = try c.int(u64);
        const mtime_ns = try c.int(i64);
        const inode = try c.int(u64);
        const flags = try c.int(u8);
        r.* = .{
            .path = path,
            .entry = .{
                .size = size,
                .mtime_ns = mtime_ns,
                .inode = inode,
                .flags = @bitCast(flags),
            },
        };
    }
    return recs;
}

const Cursor = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn take(c: *Cursor, n: usize) error{Corrupt}![]const u8 {
        if (c.bytes.len - c.pos < n) return error.Corrupt;
        const out = c.bytes[c.pos..][0..n];
        c.pos += n;
        return out;
    }

    fn int(c: *Cursor, comptime T: type) error{Corrupt}!T {
        const b = try c.take(@sizeOf(T));
        return std.mem.readInt(T, b[0..@sizeOf(T)], .little);
    }
};

// Binary search; old records are sorted by path.
fn findOld(old: []const OldRecord, key: []const u8) ?*const OldRecord {
    var lo: usize = 0;
    var hi: usize = old.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (std.mem.order(u8, old[mid].path, key)) {
            .eq => return &old[mid],
            .lt => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return null;
}

fn putInt(list: *std.ArrayList(u8), gpa: Allocator, comptime T: type, v: T) !void {
    var buf: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buf, v, .little);
    try list.appendSlice(gpa, &buf);
}

fn writeManifest(
    gpa: Allocator,
    io: Io,
    path: []const u8,
    config_hash: u64,
    records: []const Record,
) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);

    try putInt(&buf, gpa, u32, manifest_magic);
    try putInt(&buf, gpa, u64, config_hash);
    try putInt(&buf, gpa, u32, @intCast(records.len));
    for (records) |r| {
        try putInt(&buf, gpa, u32, @intCast(r.path.len));
        try buf.appendSlice(gpa, r.path);
        try putInt(&buf, gpa, u64, r.entry.size);
        try putInt(&buf, gpa, i64, r.entry.mtime_ns);
        try putInt(&buf, gpa, u64, r.entry.inode);
        const flags: u8 = @bitCast(r.entry.flags);
        try buf.append(gpa, flags);
    }
    try putInt(&buf, gpa, u64, std.hash.Wyhash.hash(0, buf.items));

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = buf.items });
}

fn writeOutputModule(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    scan_root: []const u8,
    path: []const u8,
    matches: []const []const u8,
) !void {
    const output_dir = std.fs.path.dirname(path) orelse ".";
    try Io.Dir.cwd().createDirPath(io, output_dir);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, "// Generated by the class-file scan (zig build scan). Do not edit.\n\n");

    const cwd_path = try Io.Dir.cwd().realPathFileAlloc(io, ".", arena);
    var aliases: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer aliases.deinit(gpa);
    for (matches) |m| {
        const base_alias = try aliasFromPath(arena, m);
        const alias = try uniqueAlias(arena, &aliases, base_alias);
        try aliases.put(gpa, alias, m);

        const file_path = try std.fs.path.join(arena, &.{ scan_root, m });
        const import_path = try std.fs.path.relativeAlloc(
            arena,
            cwd_path,
            null,
            output_dir,
            file_path,
        );
        for (import_path) |*c| {
            if (c.* == '\\') c.* = '/';
        }
        if (std.fs.path.isAbsolute(import_path)) {
            std.log.err("generated import for '{s}' is outside the output module root", .{m});
            return error.ImportOutsideModule;
        }
        try out.print(gpa, "pub const {f} = @import(\"{f}\");\n", .{
            std.zig.fmtId(alias),
            std.zig.fmtString(import_path),
        });
    }

    const cwd = Io.Dir.cwd();
    if (cwd.readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024))) |existing| {
        defer gpa.free(existing);
        if (std.mem.eql(u8, existing, out.items)) return;
    } else |_| {}

    try cwd.writeFile(io, .{ .sub_path = path, .data = out.items });
}

fn aliasFromPath(arena: Allocator, relative_path: []const u8) ![]const u8 {
    const stem = std.fs.path.stem(relative_path);
    if (stem.len == 0) return arena.dupe(u8, "class");
    return stem;
}
/// Keeps the file stem unless another alias already owns it.
fn uniqueAlias(
    arena: Allocator,
    aliases: *const std.StringHashMapUnmanaged([]const u8),
    base: []const u8,
) ![]const u8 {
    const reserved = base.len == 7 and std.mem.eql(u8, base, "Extends");
    const first = if (reserved) try std.fmt.allocPrint(arena, "{s}Class", .{base}) else base;
    if (aliases.get(first) == null) return first;
    var suffix: u32 = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(arena, "{s}{d}", .{ first, suffix });
        if (aliases.get(candidate) == null) return candidate;
    }
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zlob = @import("zlob");
