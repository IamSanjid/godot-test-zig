pub const Options = struct {
    /// Only files with one of these extensions are returned (include the dot).
    extensions: []const []const u8 = &.{".zig"},
    /// Directory names to skip entirely, matched against each directory's own name.
    exclude_dirs: []const []const u8 = &.{ ".git", ".zig-cache", "zig-out" },
    /// Wildcard patterns (`*`, `?`) matched against file names, e.g. "*_test.zig".
    exclude_files: []const []const u8 = &.{},
};

/// Minimal glob: `*` matches any run of characters, `?` matches exactly one.
fn globMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var mark: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            mark = t;
            p += 1;
        } else if (star) |s| {
            p = s + 1;
            mark += 1;
            t = mark;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn anyGlob(patterns: []const []const u8, name: []const u8) bool {
    for (patterns) |pat| if (globMatch(pat, name)) return true;
    return false;
}

fn hasExt(name: []const u8, exts: []const []const u8) bool {
    for (exts) |e| if (std.mem.endsWith(u8, name, e)) return true;
    return false;
}

/// Returns paths relative to `root`, using '/' separators. Caller frees each
/// path and the list.
pub fn findFiles(
    gpa: Allocator,
    io: Io,
    root: Io.Dir,
    opts: Options,
) !std.ArrayList([]const u8) {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |p| gpa.free(p);
        out.deinit(gpa);
    }
    try scan(gpa, io, root, "", opts, &out);
    return out;
}

fn scan(
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    prefix: []const u8, // path of `dir` relative to the root, "" for the root
    opts: Options,
    out: *std.ArrayList([]const u8),
) !void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (anyGlob(opts.exclude_dirs, entry.name)) continue; // prune
                const sub_path = try joinPath(gpa, prefix, entry.name);
                defer gpa.free(sub_path);

                var sub = try dir.openDir(io, entry.name, .{ .iterate = true });
                defer sub.close(io);
                try scan(gpa, io, sub, sub_path, opts, out);
            },
            .file => {
                if (!hasExt(entry.name, opts.extensions)) continue;
                if (anyGlob(opts.exclude_files, entry.name)) continue;
                try out.append(gpa, try joinPath(gpa, prefix, entry.name));
            },
            else => {}, // symlinks, etc.: skipped on purpose
        }
    }
}

fn joinPath(gpa: Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    if (prefix.len == 0) return gpa.dupe(u8, name);
    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ prefix, name });
}

test globMatch {
    try std.testing.expect(globMatch("*_test.zig", "foo_test.zig"));
    try std.testing.expect(globMatch("godot/*/*_test.zig", "godot/test/foo_test.zig"));
    try std.testing.expect(!globMatch("*_test.zig", "foo.zig"));
    try std.testing.expect(globMatch("a?c", "abc"));
    try std.testing.expect(globMatch("*", "anything"));
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
