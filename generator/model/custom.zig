//! Shared custom-code sections for bindgen and codegen.
//!
//! Custom files mirror the generated artifact path below their backend's
//! `custom/` directory. Every block has an explicit placement:
//!
//!   // @section file
//!   // @section artifact name
//!   // @section nested Target[,true]
//!   // @section replace method
//!
//! Each block ends with the matching `@section_end` line.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const names = @import("names.zig");

pub const Placement = enum { file, artifact, nested, replace };

pub const Section = struct {
    placement: Placement,
    /// Artifact label, nested target, or replacement name. Empty for `file`.
    name: []const u8 = "",
    /// Bindgen nested sections may be inherited by child classes.
    emit_child: bool = false,
    code: []const u8,
};

pub const StructSection = struct {
    type_name: []const u8,
    emit_child: bool = false,
    code: []const u8,
};

pub const Sections = struct {
    sections: []const Section = &.{},
    imports: []const u8 = "",
    methods: []const Section = &.{},
    replacements: []const Section = &.{},
    structs: []const StructSection = &.{},

    pub fn fileCode(self: Sections) []const u8 {
        return self.imports;
    }

    pub fn nestedCode(self: Sections, target: []const u8) []const u8 {
        for (self.structs) |section| {
            if (std.mem.eql(u8, section.type_name, target)) return section.code;
        }
        return "";
    }

    pub fn codeForStruct(self: Sections, target: []const u8) []const u8 {
        return self.nestedCode(target);
    }

    pub fn hasNestedChild(self: Sections, target: []const u8) bool {
        for (self.structs) |section| {
            if (section.emit_child and std.mem.eql(u8, section.type_name, target)) return true;
        }
        return false;
    }

    pub fn replacementIndex(self: Sections, name: []const u8) ?usize {
        for (self.replacements, 0..) |section, index| {
            if (std.mem.eql(u8, section.name, name)) return index;
        }
        return null;
    }

    pub fn hasPlacement(self: Sections, placement: Placement) bool {
        for (self.sections) |section| {
            if (section.placement == placement) return true;
        }
        return false;
    }
};

pub fn read(
    arena: Allocator,
    io: Io,
    root: []const u8,
    relative_path: []const u8,
) !?Sections {
    const path = try std.fs.path.join(arena, &.{ root, relative_path });
    const raw_input = Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const raw = if (std.mem.startsWith(u8, raw_input, "\xEF\xBB\xBF")) raw_input[3..] else raw_input;
    return try parse(arena, raw);
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    var sections: [64]Section = undefined;
    var section_count: usize = 0;
    var active: ?Placement = null;
    var active_name: []const u8 = "";
    var active_emit_child = false;
    var active_aw: Io.Writer.Allocating = .init(arena);

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");

        if (std.mem.startsWith(u8, trimmed, "// @section_end")) {
            const spec = std.mem.trim(u8, trimmed["// @section_end".len..], " ");
            if (active == null) return error.UnexpectedSectionEnd;
            const end = try parseHeader(spec);
            if (end.placement != active.? or !std.mem.eql(u8, end.name, active_name)) {
                return error.MismatchedSectionEnd;
            }
            if (section_count == sections.len) return error.TooManyCustomSections;
            sections[section_count] = .{
                .placement = active.?,
                .name = try arena.dupe(u8, active_name),
                .emit_child = active_emit_child,
                .code = try arena.dupe(u8, active_aw.writer.buffered()),
            };
            section_count += 1;
            active = null;
            active_name = "";
            active_emit_child = false;
            active_aw = .init(arena);
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "// @section ")) {
            if (active != null) return error.UnclosedCustomSection;
            const header = try parseHeader(std.mem.trim(u8, trimmed["// @section ".len..], " "));
            active = header.placement;
            active_name = header.name;
            active_emit_child = header.emit_child;
            for (sections[0..section_count]) |existing| {
                if (header.placement != .nested and existing.placement != .nested and
                    std.mem.eql(u8, existing.name, header.name))
                {
                    return error.DuplicateCustomSection;
                }
            }
            continue;
        }

        if (active) |_| {
            try active_aw.writer.print("{s}\n", .{line});
        }
    }

    if (active != null) return error.UnclosedCustomSection;

    var file_code: []const u8 = "";
    var artifacts: [64]Section = undefined;
    var artifact_count: usize = 0;
    var replacements: [64]Section = undefined;
    var replacement_count: usize = 0;
    var structs: [64]StructSection = undefined;
    var struct_count: usize = 0;
    for (sections[0..section_count]) |section| {
        switch (section.placement) {
            .file => file_code = section.code,
            .artifact => {
                artifacts[artifact_count] = section;
                artifact_count += 1;
            },
            .replace => {
                replacements[replacement_count] = section;
                replacement_count += 1;
            },
            .nested => {
                structs[struct_count] = .{
                    .type_name = section.name,
                    .emit_child = section.emit_child,
                    .code = section.code,
                };
                struct_count += 1;
            },
        }
    }

    return .{
        .sections = try arena.dupe(Section, sections[0..section_count]),
        .imports = file_code,
        .methods = try arena.dupe(Section, artifacts[0..artifact_count]),
        .replacements = try arena.dupe(Section, replacements[0..replacement_count]),
        .structs = try arena.dupe(StructSection, structs[0..struct_count]),
    };
}

const Header = struct {
    placement: Placement,
    name: []const u8 = "",
    emit_child: bool = false,
};

fn parseHeader(spec: []const u8) !Header {
    const space = std.mem.indexOfScalar(u8, spec, ' ');
    const placement_text = if (space) |index| spec[0..index] else spec;
    const rest = if (space) |index| std.mem.trim(u8, spec[index + 1 ..], " ") else "";
    const placement = std.meta.stringToEnum(Placement, placement_text) orelse
        return error.InvalidCustomPlacement;

    if (placement == .file) {
        if (rest.len != 0) return error.InvalidCustomPlacement;
        return .{ .placement = .file };
    }
    if (rest.len == 0) return error.InvalidCustomPlacement;

    var name = rest;
    var emit_child = false;
    if (placement == .nested) {
        if (std.mem.indexOfScalar(u8, rest, ',')) |comma| {
            name = std.mem.trim(u8, rest[0..comma], " ");
            emit_child = std.mem.eql(u8, std.mem.trim(u8, rest[comma + 1 ..], " "), "true");
        }
    }
    if (!names.isValidMemberName(name)) return error.InvalidCustomName;
    return .{ .placement = placement, .name = name, .emit_child = emit_child };
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

test "shared custom sections" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const sections = try parse(arena,
        \\// @section file
        \\const a = 1;
        \\// @section_end file
        \\// @section nested Object,true
        \\const b = 2;
        \\// @section_end nested Object
        \\// @section artifact extra
        \\const c = 3;
        \\// @section_end artifact extra
        \\// @section replace process
        \\const d = 4;
        \\// @section_end replace process
    );
    try std.testing.expectEqualStrings("const a = 1;\n", sections.fileCode());
    try std.testing.expectEqualStrings("const b = 2;\n", sections.nestedCode("Object"));
    try std.testing.expect(sections.hasNestedChild("Object"));
    try std.testing.expectEqualStrings("extra", sections.sections[2].name);
    try std.testing.expectEqualStrings("const c = 3;\n", sections.sections[2].code);
    try std.testing.expectEqualStrings("const d = 4;\n", sections.sections[3].code);
}

test "shared custom markers reject mismatches" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectError(error.MismatchedSectionEnd, parse(arena,
        \\// @section artifact one
        \\// @section_end artifact two
    ));
    try std.testing.expectError(error.DuplicateCustomSection, parse(arena,
        \\// @section artifact one
        \\// @section_end artifact one
        \\// @section artifact one
        \\// @section_end artifact one
    ));
    try std.testing.expectError(error.InvalidCustomPlacement, parse(arena,
        \\// @section unknown one
        \\// @section_end unknown one
    ));
}
