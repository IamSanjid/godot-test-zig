//! Shared custom-code sections for bindgen and codegen.
//!
//! Custom files mirror the generated artifact path below their backend's
//! `custom/` directory. Every block has an explicit placement:
//!
//!   // @section file
//!   // @section artifact name
//!   // @section extend Target[,true]
//!   // @section replace method
//!
//! `extend` appends raw declarations inside the generated declaration or scope
//! named `Target`; `,true` keeps the class-scope propagation behavior. Artifact
//! and replacement names and `extend` targets are separate namespaces; each
//! rejects duplicate names in the same file.
//! Each block ends with the matching `@section_end` line.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const names = @import("names.zig");

pub const Placement = enum { file, artifact, extend, replace };

pub const Section = struct {
    placement: Placement,
    /// Artifact label, extension target, or replacement name. Empty for `file`.
    name: []const u8 = "",
    /// `extend` sections marked with `,true` are inherited by child classes.
    propagate: bool = false,
    code: []const u8,
};

/// One raw-code block attached to a generated declaration or scope.
pub const ExtensionSection = struct {
    target: []const u8,
    propagate: bool = false,
    code: []const u8,
};

pub const Sections = struct {
    sections: []const Section = &.{},
    imports: []const u8 = "",
    methods: []const Section = &.{},
    replacements: []const Section = &.{},
    extensions: []const ExtensionSection = &.{},

    pub fn fileCode(self: Sections) []const u8 {
        return self.imports;
    }

    /// Raw code attached to the generated declaration or scope named `target`.
    pub fn extensionCode(self: Sections, target: []const u8) []const u8 {
        for (self.extensions) |section| {
            if (std.mem.eql(u8, section.target, target)) return section.code;
        }
        return "";
    }

    /// Whether an inheritable extension targets `target`.
    pub fn hasExtension(self: Sections, target: []const u8) bool {
        for (self.extensions) |section| {
            if (section.propagate and std.mem.eql(u8, section.target, target)) return true;
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
    var active_propagate = false;
    var active_aw: Io.Writer.Allocating = .init(arena);

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");

        if (std.mem.startsWith(u8, trimmed, "// @section_end")) {
            const spec = std.mem.trim(u8, trimmed["// @section_end".len..], " ");
            const current = active orelse return error.UnexpectedSectionEnd;
            const end = try parseHeader(spec);
            if (end.placement != current or !std.mem.eql(u8, end.name, active_name)) {
                return error.MismatchedSectionEnd;
            }
            if (section_count == sections.len) return error.TooManyCustomSections;
            sections[section_count] = .{
                .placement = current,
                .name = try arena.dupe(u8, active_name),
                .propagate = active_propagate,
                .code = try arena.dupe(u8, active_aw.writer.buffered()),
            };
            section_count += 1;
            active = null;
            active_name = "";
            active_propagate = false;
            active_aw = .init(arena);
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "// @section ")) {
            if (active != null) return error.UnclosedCustomSection;
            const header = try parseHeader(std.mem.trim(u8, trimmed["// @section ".len..], " "));
            active = header.placement;
            active_name = header.name;
            active_propagate = header.propagate;
            for (sections[0..section_count]) |existing| {
                if (!std.mem.eql(u8, existing.name, header.name)) continue;
                // Artifact/replacement names and extend targets are separate
                // namespaces; each namespace rejects its own duplicates.
                if (header.placement == .extend and existing.placement == .extend) {
                    return error.DuplicateCustomSection;
                }
                if (header.placement != .extend and existing.placement != .extend) {
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
    var extensions: [64]ExtensionSection = undefined;
    var extension_count: usize = 0;
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
            .extend => {
                extensions[extension_count] = .{
                    .target = section.name,
                    .propagate = section.propagate,
                    .code = section.code,
                };
                extension_count += 1;
            },
        }
    }

    return .{
        .sections = try arena.dupe(Section, sections[0..section_count]),
        .imports = file_code,
        .methods = try arena.dupe(Section, artifacts[0..artifact_count]),
        .replacements = try arena.dupe(Section, replacements[0..replacement_count]),
        .extensions = try arena.dupe(ExtensionSection, extensions[0..extension_count]),
    };
}

const Header = struct {
    placement: Placement,
    name: []const u8 = "",
    propagate: bool = false,
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
    var propagate = false;
    if (placement == .extend) {
        if (std.mem.indexOfScalar(u8, rest, ',')) |comma| {
            name = std.mem.trim(u8, rest[0..comma], " ");
            propagate = std.mem.eql(u8, std.mem.trim(u8, rest[comma + 1 ..], " "), "true");
        }
    }
    if (!names.isValidMemberName(name)) return error.InvalidCustomName;
    return .{ .placement = placement, .name = name, .propagate = propagate };
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
        \\// @section extend Object,true
        \\const b = 2;
        \\// @section_end extend Object
        \\// @section artifact extra
        \\const c = 3;
        \\// @section_end artifact extra
        \\// @section replace process
        \\const d = 4;
        \\// @section_end replace process
    );
    try std.testing.expectEqualStrings("const a = 1;\n", sections.fileCode());
    try std.testing.expectEqualStrings("const b = 2;\n", sections.extensionCode("Object"));
    try std.testing.expectEqualStrings("", sections.extensionCode("Missing"));
    try std.testing.expect(sections.hasExtension("Object"));
    try std.testing.expect(!sections.hasExtension("Missing"));
    try std.testing.expectEqualStrings("extra", sections.sections[2].name);
    try std.testing.expectEqualStrings("const c = 3;\n", sections.sections[2].code);
    try std.testing.expectEqualStrings("const d = 4;\n", sections.sections[3].code);
}

test "shared custom extensions without propagation" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const sections = try parse(arena,
        \\// @section extend Required
        \\const a = 1;
        \\// @section_end extend Required
    );
    try std.testing.expectEqualStrings("const a = 1;\n", sections.extensionCode("Required"));
    try std.testing.expect(!sections.hasExtension("Required"));
}

test "shared custom extensions reject duplicate targets" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectError(error.DuplicateCustomSection, parse(arena,
        \\// @section extend Object
        \\const a = 1;
        \\// @section_end extend Object
        \\// @section extend Object,true
        \\const b = 2;
        \\// @section_end extend Object
    ));

    // Extend targets and artifact names are separate namespaces.
    const sections = try parse(arena,
        \\// @section extend Object
        \\const a = 1;
        \\// @section_end extend Object
        \\// @section artifact Object
        \\const b = 2;
        \\// @section_end artifact Object
    );
    try std.testing.expectEqualStrings("const a = 1;\n", sections.extensionCode("Object"));
    try std.testing.expectEqualStrings("Object", sections.methods[0].name);
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
    // The old `nested` placement was renamed to `extend`.
    try std.testing.expectError(error.InvalidCustomPlacement, parse(arena,
        \\// @section nested Object
        \\// @section_end nested Object
    ));
}
