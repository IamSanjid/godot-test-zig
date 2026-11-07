//! GDExtension interface table emission.
//!
//! `InterfaceJson.interface` describes the functions resolved through
//! `GDExtensionInterfaceGetProcAddress`. The generated `Procs` struct holds
//! one non-optional function pointer per entry and an `init` helper that loads
//! every pointer, failing with a diagnostic that names the missing function.

pub fn emit(
    writer: *Io.Writer,
    registry: Registry,
    functions: []const InterfaceJson.InterfaceFunction,
    strip_deprecation: bool,
) !void {
    var field_count: usize = 0;
    for (functions) |function| {
        if (isStripped(function, strip_deprecation)) continue;
        field_count += 1;
    }

    // The get-proc-address typedef is itself part of the wrapper. Fall back to
    // the translated declaration if a future interface JSON drops it.
    const get_proc_address_type = if (registry.get("GDExtensionInterfaceGetProcAddress")) |entry|
        entry.zig
    else
        "gdi.GDExtensionInterfaceGetProcAddress";

    try writer.writeAll("pub const Procs = struct {\n");

    for (functions) |function| {
        if (isStripped(function, strip_deprecation)) continue;

        try writeComment(writer, registry, function);
        try writer.writeAll("    ");
        try common.writeIdent(writer, .camel, function.name);
        try writer.writeAll(": *const fn (");
        for (function.arguments, 0..) |argument, index| {
            if (argument.name) |name| {
                try common.writeIdent(writer, .snake, name);
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
        try writer.writeAll(",\n");
    }

    try writer.writeAll(
        \\
        \\    pub const Diagnostics = struct {
        \\        function: [64]u8 = @splat(0),
        \\
        \\        pub const Where = struct {
        \\            function: []const u8,
        \\        };
        \\
        \\        pub fn fail(maybe_diags: ?*Diagnostics, where: Where, err: anyerror) anyerror {
        \\            const diags = maybe_diags orelse return err;
        \\            std.mem.copyForwards(u8, diags.function[0..], where.function);
        \\            return err;
        \\        }
        \\
        \\        pub fn format(self: Diagnostics, w: *std.Io.Writer) !void {
        \\            try w.print("Function: {s}", .{std.mem.sliceTo(&self.function, 0)});
        \\        }
        \\    };
        \\
    );

    try writer.print(
        "    pub fn init(getProcAddress: Child({s}), diags: ?*Diagnostics) !@This() {{\n",
        .{get_proc_address_type},
    );
    if (field_count == 0) {
        try writer.writeAll("        return .{};\n");
    } else {
        try writer.writeAll("        return .{\n");
        for (functions) |function| {
            if (isStripped(function, strip_deprecation)) continue;

            try writer.writeAll("            .");
            try common.writeIdent(writer, .camel, function.name);
            try writer.print(
                " = @ptrCast(getProcAddress(\"{s}\") orelse return Diagnostics.fail(diags, .{{ .function = \"{s}\" }}, error.FunctionNotFound)),\n",
                .{ function.name, function.name },
            );
        }
        try writer.writeAll("        };\n");
    }
    try writer.writeAll("    }\n};\n");
}

fn writeComment(writer: *Io.Writer, registry: Registry, function: InterfaceJson.InterfaceFunction) !void {
    try common.writeDesc(writer, function.description, 4, 3);
    if (function.description.len != 0) try writer.writeAll("    ///\n");

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

test "interface table and init" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionInterfaceGetProcAddress", .data = .{ .function = .{ .arguments = &.{} } } },
        .{ .name = "GDExtensionInterfaceFunctionPtr", .data = .{ .function = .{ .arguments = &.{} } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    const functions = [_]InterfaceJson.InterfaceFunction{
        .{
            .name = "mem_alloc2",
            .return_value = .{ .type = "void*" },
            .arguments = &.{
                .{ .name = "p_bytes", .type = "size_t" },
                .{ .name = "p_padding", .type = "GDExtensionBool" },
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
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const Procs = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "memAlloc2: *const fn (p_bytes: usize, p_padding: bool) callconv(.c) ?*anyopaque,") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".memAlloc2 = @ptrCast(getProcAddress(\"mem_alloc2\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub const Diagnostics = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn init(getProcAddress: Child(InterfaceGetProcAddress)") != null);

    // Deprecation filtering omits the whole field and its initializer.
    var stripped: Io.Writer.Allocating = .init(std.testing.allocator);
    defer stripped.deinit();
    try emit(&stripped.writer, registry, &functions, true);
    try std.testing.expect(std.mem.indexOf(u8, stripped.writer.buffered(), "oldFunction") == null);
    try std.testing.expect(std.mem.indexOf(u8, stripped.writer.buffered(), "memAlloc2") != null);
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
