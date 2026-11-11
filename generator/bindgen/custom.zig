//! Custom-code sections for generated files.
//!
//! A custom file mirrors the generated file path relative to the output root,
//! but lives under `generator/bindgen/custom/`. For example:
//!
//!   output: builtins/string_name.zig
//!   custom: generator/bindgen/custom/builtins/string_name.zig

pub const StructSection = struct {
    type_name: []const u8,
    emit_child: bool = false,
    code: []const u8,
};

pub const Sections = struct {
    namespace_code: []const u8 = "",
    structs: []const StructSection = &.{},

    pub fn codeForStruct(self: Sections, type_name: []const u8) []const u8 {
        for (self.structs) |section| {
            if (std.mem.eql(u8, section.type_name, type_name)) return section.code;
        }
        return "";
    }

    pub fn hasChildStructs(self: Sections, type_name: []const u8) bool {
        for (self.structs) |section| {
            if (section.emit_child and std.mem.eql(u8, section.type_name, type_name)) return true;
        }
        return false;
    }
};

const Mode = union(enum) {
    namespace,
    struct_: struct {
        type_name: []const u8,
        emit_child: bool,
    },
    none,
};

/// Reads `generator/bindgen/custom/<relative_path>` and parses its sections.
/// Returns null when the custom file does not exist.
pub fn readForOutput(
    arena: Allocator,
    io: Io,
    relative_path: []const u8,
) !?Sections {
    const custom_path = try std.fs.path.join(arena, &.{ "generator/bindgen/custom", relative_path });
    const raw_input = Io.Dir.cwd().readFileAlloc(io, custom_path, arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const raw = if (std.mem.startsWith(u8, raw_input, "\xEF\xBB\xBF")) raw_input[3..] else raw_input;
    return try parse(arena, raw);
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    var namespace_aw: Io.Writer.Allocating = .init(arena);
    var current_aw: Io.Writer.Allocating = .init(arena);
    var sections: [64]StructSection = undefined;
    var section_count: usize = 0;

    var mode: Mode = .namespace;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.eql(u8, trimmed, "// @namespace") or std.mem.eql(u8, trimmed, "// @namespace_end")) {
            const is_end = std.mem.eql(u8, trimmed, "// @namespace_end");
            if (is_end) {
                switch (mode) {
                    .namespace => {},
                    else => return error.UnexpectedNamespaceEnd,
                }
            }
            try flush(arena, &mode, &current_aw, &sections, &section_count);
            mode = if (is_end) .none else .namespace;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @struct_end")) {
            const spec = std.mem.trim(u8, trimmed["// @struct_end".len..], " ");
            switch (mode) {
                .struct_ => |info| {
                    if (spec.len != 0 and !std.mem.eql(u8, spec, info.type_name)) {
                        return error.MismatchedStructEnd;
                    }
                },
                else => return error.UnexpectedStructEnd,
            }
            try flush(arena, &mode, &current_aw, &sections, &section_count);
            mode = .none;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @struct ")) {
            try flush(arena, &mode, &current_aw, &sections, &section_count);
            const spec = std.mem.trim(u8, trimmed["// @struct ".len..], " ");
            const comma = std.mem.indexOfScalar(u8, spec, ',');
            const type_name = if (comma) |index| std.mem.trim(u8, spec[0..index], " ") else spec;
            const emit_child = if (comma) |index| std.mem.eql(u8, std.mem.trim(u8, spec[index + 1 ..], " "), "true") else false;
            if (type_name.len == 0) return error.InvalidCustomMarker;
            mode = .{ .struct_ = .{ .type_name = type_name, .emit_child = emit_child } };
            continue;
        }

        switch (mode) {
            .namespace => try namespace_aw.writer.print("{s}\n", .{line}),
            .struct_ => try current_aw.writer.print("{s}\n", .{line}),
            .none => {},
        }
    }

    try flush(arena, &mode, &current_aw, &sections, &section_count);
    return .{
        .namespace_code = namespace_aw.writer.buffered(),
        .structs = try arena.dupe(StructSection, sections[0..section_count]),
    };
}

fn flush(
    arena: Allocator,
    mode: *const Mode,
    current_aw: *Io.Writer.Allocating,
    sections: *[64]StructSection,
    section_count: *usize,
) !void {
    switch (mode.*) {
        .namespace => {},
        .struct_ => |info| {
            if (section_count.* == sections.len) return error.TooManyCustomSections;
            sections[section_count.*] = .{
                .type_name = info.type_name,
                .emit_child = info.emit_child,
                .code = try arena.dupe(u8, current_aw.writer.buffered()),
            };
            section_count.* += 1;
            current_aw.* = .init(arena);
        },
        .none => {},
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

test "custom sections and end markers" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const sections = try parse(arena,
        \\// @namespace
        \\const a = 1;
        \\// @namespace_end
        \\// @struct Object
        \\const b = 2;
        \\// @struct_end Object
        \\// @struct Virtual,true
        \\const c = 3;
        \\// @struct_end Virtual
    );
    try std.testing.expectEqualStrings("const a = 1;\n", sections.namespace_code);
    try std.testing.expectEqual(@as(usize, 2), sections.structs.len);
    try std.testing.expectEqualStrings("Object", sections.structs[0].type_name);
    try std.testing.expectEqualStrings("const b = 2;\n", sections.structs[0].code);
    try std.testing.expectEqualStrings("Virtual", sections.structs[1].type_name);
    try std.testing.expect(sections.structs[1].emit_child);
}

test "struct end must match the active struct" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectError(error.MismatchedStructEnd, parse(arena,
        \\// @struct Object
        \\const b = 2;
        \\// @struct_end Node
    ));
}
