//! GDExtension interface tag/type emission.
//!
//! `InterfaceJson.interface` describes the functions resolved through
//! `GDExtensionInterfaceGetProcAddress`. The generated file exposes:
//!
//! * `ProcsTag`: an enum of raw interface names, for table indexing.
//! * `ProcsTypes`: one `pub const <raw_name> = *const fn (...) ...` alias per
//!   interface function.
//!
//! Raw C names are kept verbatim; no case conversion is applied.
//! Documentation, argument documentation, `Since`, and deprecation notes are
//! attached to both the enum tags and the type aliases.

pub fn emit(
    writer: *Io.Writer,
    registry: Registry,
    functions: []const InterfaceJson.InterfaceFunction,
    strip_deprecation: bool,
) !void {
    try writer.writeAll("pub const ProcsTag = enum {\n");
    for (functions) |function| {
        if (isStripped(function, strip_deprecation)) continue;

        try writeComment(writer, registry, function);
        try writer.writeAll("    ");
        try writeRawIdent(writer, function.name);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("pub const ProcsTypes = struct {\n");
    for (functions) |function| {
        if (isStripped(function, strip_deprecation)) continue;

        try writeComment(writer, registry, function);
        try writer.writeAll("    pub const ");
        try writeRawIdent(writer, function.name);
        try writer.writeAll(" = *const fn (");
        for (function.arguments, 0..) |argument, index| {
            if (argument.name) |name| {
                try writeRawIdent(writer, name);
                try writer.writeAll(": ");
            }
            try common.writeType(writer, registry, argument.type);
            if (index + 1 < function.arguments.len) try writer.writeAll(", ");
        }
        try writer.print(") callconv(.{s}) ", .{@tagName(.c)});
        if (function.return_value) |return_value| {
            try common.writeType(writer, registry, return_value.type);
        } else {
            try writer.writeAll("void");
        }
        try writer.writeAll(";\n");
    }
    try writer.writeAll("};\n");
}

fn writeRawIdent(writer: *Io.Writer, name: []const u8) !void {
    if (std.zig.isValidId(name)) {
        try writer.writeAll(name);
    } else {
        try writer.print("@\"{s}\"", .{name});
    }
}

fn writeComment(writer: *Io.Writer, registry: Registry, function: InterfaceJson.InterfaceFunction) !void {
    var wrote_content = false;

    if (function.description.len != 0) {
        try common.writeDesc(writer, function.description, 4, 3);
        wrote_content = true;
    }

    if (function.return_value) |return_value| {
        if (return_value.description) |description| {
            if (description.len != 0) {
                if (wrote_content) try writer.writeAll("    ///\n");
                try writer.writeAll("    /// Returns:\n");
                for (description) |line| {
                    try writer.print("    ///   {s}\n", .{line});
                }
                wrote_content = true;
            }
        }
    }

    var has_argument_docs = false;
    for (function.arguments) |argument| {
        if (argument.description) |description| {
            if (description.len != 0) {
                has_argument_docs = true;
                break;
            }
        }
    }

    if (has_argument_docs) {
        if (wrote_content) try writer.writeAll("    ///\n");
        try writer.writeAll("    /// Arguments:\n");
        for (function.arguments) |argument| {
            const description = argument.description orelse continue;
            if (description.len == 0) continue;

            const name = argument.name orelse "arg";
            try writer.print("    ///   {s}: {s}\n", .{ name, description[0] });
            for (description[1..]) |line| {
                try writer.print("    ///       {s}\n", .{line});
            }
        }
        wrote_content = true;
    }

    if (wrote_content) try writer.writeAll("    ///\n");

    try writer.print("    /// Since: {s}\n", .{function.since});
    try common.writeDeprecated(writer, registry, function.deprecated, 4, 3);
    if (function.see) |see| {
        for (see) |link| try writer.print("    /// See: {s}\n", .{link});
    }
    if (function.legacy_type_name) |legacy_type_name| {
        try writer.print("    /// Legacy type name: {s}\n", .{legacy_type_name});
    }
}

fn isStripped(function: InterfaceJson.InterfaceFunction, strip_deprecation: bool) bool {
    return strip_deprecation and function.deprecated != null;
}

test "interface tags and type aliases" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionInterfaceGetProcAddress", .data = .{ .function = .{ .arguments = &.{} } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    const functions = [_]InterfaceJson.InterfaceFunction{
        .{
            .name = "mem_alloc2",
            .return_value = .{
                .type = "void*",
                .description = &.{"A pointer to the allocated memory."},
            },
            .arguments = &.{
                .{
                    .name = "p_bytes",
                    .type = "size_t",
                    .description = &.{"The amount of memory to allocate in bytes."},
                },
                .{
                    .name = "p_padding",
                    .type = "GDExtensionBool",
                    .description = &.{"Whether to request padding."},
                },
            },
            .description = &.{"Allocates memory."},
            .since = "4.6",
        },
        .{
            .name = "old_function",
            .arguments = &.{},
            .description = &.{},
            .since = "4.1",
            .deprecated = .{ .since = "4.4", .replace_with = "new_function" },
        },
    };

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emit(&aw.writer, registry, &functions, false);

    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const ProcsTag = enum {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const ProcsTypes = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\n    mem_alloc2,\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const mem_alloc2 = *const fn (p_bytes: usize, p_padding: bool) callconv(.c) ?*anyopaque;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "/// Arguments:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "///   p_bytes: The amount of memory to allocate in bytes.") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "/// Returns:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "/// Since: 4.6") != null);

    // No camel-case conversion and no generated loader.
    try std.testing.expect(std.mem.indexOf(u8, output, "memAlloc2") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const Procs = struct") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Diagnostics") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn init") == null);

    // Deprecation filtering omits both the tag and the type alias.
    var stripped: Io.Writer.Allocating = .init(std.testing.allocator);
    defer stripped.deinit();
    try emit(&stripped.writer, registry, &functions, true);
    try std.testing.expect(std.mem.indexOf(u8, stripped.writer.buffered(), "old_function") == null);
    try std.testing.expect(std.mem.indexOf(u8, stripped.writer.buffered(), "mem_alloc2") != null);
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../model/InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
