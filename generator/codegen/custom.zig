//! Project-side custom overlays for codegen artifacts.
//!
//! Custom files mirror the generated artifact path below `generator/codegen/custom/`.
//! They are read, never created or overwritten. Supported directives are:
//!
//!   // @imports
//!   ...
//!   // @imports_end
//!
//!   // @replace methodName
//!   ...
//!   // @replace_end methodName
//!
//!   // @method addedName
//!   ...
//!   // @method_end addedName

pub const Section = struct {
    name: []const u8,
    code: []const u8,
};

pub const Sections = struct {
    imports: []const u8 = "",
    replacements: []const Section = &.{},
    methods: []const Section = &.{},

    pub fn replacement(self: Sections, name: []const u8) ?Section {
        for (self.replacements) |section| {
            if (std.mem.eql(u8, section.name, name)) return section;
        }
        return null;
    }

    pub fn replacementIndex(self: Sections, name: []const u8) ?usize {
        for (self.replacements, 0..) |section, index| {
            if (std.mem.eql(u8, section.name, name)) return index;
        }
        return null;
    }
};

const Entry = struct {
    name: []const u8,
    aw: Io.Writer.Allocating,
};

const Mode = union(enum) {
    none,
    imports,
    replace: Entry,
    method: Entry,
};

/// Reads `generator/codegen/custom/<relative_path>`. Returns null when the file does not
/// exist.
pub fn read(
    arena: Allocator,
    io: Io,
    relative_path: []const u8,
) !?Sections {
    const path = try std.fs.path.join(arena, &.{ "generator/codegen/custom", relative_path });
    const raw_input = Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const raw = if (std.mem.startsWith(u8, raw_input, "\xEF\xBB\xBF")) raw_input[3..] else raw_input;
    return try parse(arena, raw);
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    var imports_aw: Io.Writer.Allocating = .init(arena);
    var replacements: [64]Section = undefined;
    var replacement_count: usize = 0;
    var methods: [64]Section = undefined;
    var method_count: usize = 0;
    var imports_seen = false;
    var mode: Mode = .none;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.eql(u8, trimmed, "// @imports")) {
            if (mode != .none) return error.UnclosedCustomSection;
            if (imports_seen) return error.DuplicateImports;
            imports_seen = true;
            mode = .imports;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "// @imports_end")) {
            if (mode != .imports) return error.UnexpectedImportsEnd;
            mode = .none;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @replace_end")) {
            const name = std.mem.trim(u8, trimmed["// @replace_end".len..], " ");
            switch (mode) {
                .replace => |entry| {
                    if (!std.mem.eql(u8, entry.name, name)) return error.MismatchedReplaceEnd;
                    try appendUnique(&replacements, &replacement_count, .{
                        .name = entry.name,
                        .code = try arena.dupe(u8, entry.aw.writer.buffered()),
                    }, replacements[0..replacement_count], methods[0..method_count]);
                    mode = .none;
                },
                else => return error.UnexpectedReplaceEnd,
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @replace ")) {
            if (mode != .none) return error.UnclosedCustomSection;
            const name = std.mem.trim(u8, trimmed["// @replace ".len..], " ");
            try validateName(name);
            mode = .{ .replace = .{ .name = try arena.dupe(u8, name), .aw = .init(arena) } };
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @method_end")) {
            const name = std.mem.trim(u8, trimmed["// @method_end".len..], " ");
            switch (mode) {
                .method => |entry| {
                    if (!std.mem.eql(u8, entry.name, name)) return error.MismatchedMethodEnd;
                    try appendUnique(&methods, &method_count, .{
                        .name = entry.name,
                        .code = try arena.dupe(u8, entry.aw.writer.buffered()),
                    }, replacements[0..replacement_count], methods[0..method_count]);
                    mode = .none;
                },
                else => return error.UnexpectedMethodEnd,
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @method ")) {
            if (mode != .none) return error.UnclosedCustomSection;
            const name = std.mem.trim(u8, trimmed["// @method ".len..], " ");
            try validateName(name);
            mode = .{ .method = .{ .name = try arena.dupe(u8, name), .aw = .init(arena) } };
            continue;
        }

        switch (mode) {
            .none => {},
            .imports => try imports_aw.writer.print("{s}\n", .{line}),
            .replace => |*entry| try entry.aw.writer.print("{s}\n", .{line}),
            .method => |*entry| try entry.aw.writer.print("{s}\n", .{line}),
        }
    }

    if (mode != .none) return error.UnclosedCustomSection;

    return .{
        .imports = imports_aw.writer.buffered(),
        .replacements = try arena.dupe(Section, replacements[0..replacement_count]),
        .methods = try arena.dupe(Section, methods[0..method_count]),
    };
}

fn validateName(name: []const u8) !void {
    if (name.len == 0 or !std.zig.isValidId(name)) return error.InvalidCustomMethod;
}

fn appendUnique(
    sections: *[64]Section,
    count: *usize,
    section: Section,
    replacements: []const Section,
    methods: []const Section,
) !void {
    for (replacements) |existing| {
        if (std.mem.eql(u8, existing.name, section.name)) return error.DuplicateCustomMethod;
    }
    for (methods) |existing| {
        if (std.mem.eql(u8, existing.name, section.name)) return error.DuplicateCustomMethod;
    }
    if (count.* == sections.len) return error.TooManyCustomSections;
    sections[count.*] = section;
    count.* += 1;
}

/// Constants/enums/native/singletons do not have artifact overlays yet. Warn if
/// a user starts relying on them instead of silently ignoring the files.
pub fn warnUnsupportedArtifacts(arena: Allocator, io: Io) !void {
    const relative_paths = [_][]const u8{
        "constants.zig",
        "enums.zig",
        "native.zig",
        "singletons.zig",
    };
    for (relative_paths) |relative_path| {
        const path = try std.fs.path.join(arena, &.{ "generator/codegen/custom", relative_path });
        _ = Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        std.log.warn("Codegen custom overlay `{s}` is not handled yet; ignoring it.", .{path});
    }
}

pub fn writeRaw(writer: *Io.Writer, code: []const u8) !void {
    if (code.len == 0) return;
    try writer.writeAll(code);
    if (code[code.len - 1] != '\n') try writer.writeByte('\n');
}

pub fn writeIndented(writer: *Io.Writer, code: []const u8, indent: usize) !void {
    if (code.len == 0) return;
    const body = if (code[code.len - 1] == '\n') code[0 .. code.len - 1] else code;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        if (line.len != 0) {
            for (0..indent) |_| try writer.writeByte(' ');
            try writer.writeAll(line);
        }
        try writer.writeByte('\n');
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

test "custom sections parse imports, replacements, and additions" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const sections = try parse(arena,
        \\// @imports
        \\const helpers = @import("helpers.zig");
        \\// @imports_end
        \\// @replace process
        \\pub inline fn process(self: *Node) void {}
        \\// @replace_end process
        \\// @method extra
        \\pub inline fn extra(self: *Node) void {}
        \\// @method_end extra
    );
    try std.testing.expectEqualStrings("const helpers = @import(\"helpers.zig\");\n", sections.imports);
    try std.testing.expectEqual(@as(usize, 1), sections.replacements.len);
    try std.testing.expectEqualStrings("process", sections.replacements[0].name);
    try std.testing.expectEqual(@as(usize, 1), sections.methods.len);
    try std.testing.expectEqualStrings("extra", sections.methods[0].name);
}

test "custom duplicate and mismatched sections are rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectError(error.DuplicateCustomMethod, parse(arena,
        \\// @replace process
        \\// @replace_end process
        \\// @method process
        \\// @method_end process
    ));
    try std.testing.expectError(error.MismatchedReplaceEnd, parse(arena,
        \\// @replace process
        \\// @replace_end other
    ));
}
