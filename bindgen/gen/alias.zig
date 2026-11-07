//! Type aliases. The target is resolved with the same rules as any other type
//! reference, so aliases to wrapper structs/handles/pointers refer to the
//! wrapper declaration instead of leaking a `gdi.` name into the file.

pub fn emit(writer: *Io.Writer, registry: Registry, t: InterfaceJson.TypeDecl) !void {
    std.debug.assert(t.data == .alias);
    const alias = t.data.alias;
    const zig_name = registry.get(t.name).?.zig;

    try common.writeDeprecated(writer, registry, t.deprecated, 0, 3);
    try common.writeDesc(writer, t.description, 0, 3);
    try writer.print("pub const {s} = ", .{zig_name});
    try common.writeType(writer, registry, alias.type);
    try writer.writeAll(";\n");
}

test "aliases resolve through wrapper declarations and primitives" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionClassCreationInfo4", .data = .{ .@"struct" = .{ .members = &.{} } } },
        .{ .name = "GDExtensionClassCreationInfo5", .data = .{ .alias = .{ .type = "GDExtensionClassCreationInfo4" } } },
        .{ .name = "GDExtensionBool", .data = .{ .alias = .{ .type = "uint8_t" } } },
        .{ .name = "GDExtensionCStr", .data = .{ .alias = .{ .type = "const char*" } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    const cases = [_]struct { index: usize, expected: []const u8 }{
        .{ .index = 1, .expected = "pub const ClassCreationInfo5 = ClassCreationInfo4;\n" },
        .{ .index = 2, .expected = "pub const Bool = u8;\n" },
        .{ .index = 3, .expected = "pub const CStr = [*c]const u8;\n" },
    };

    for (cases) |case| {
        var aw: Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try emit(&aw.writer, registry, types[case.index]);
        try std.testing.expectEqualStrings(case.expected, aw.writer.buffered());
    }
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
