//! `extern struct` emission. Member order and types are kept exactly as the C
//! header declares them; only names and pointer spellings are translated.

pub fn emit(
    writer: *Io.Writer,
    registry: Registry,
    initialization: Options.MemberInitialization,
    t: InterfaceJson.TypeDecl,
) !void {
    std.debug.assert(t.data == .@"struct");
    const structure = t.data.@"struct";
    const zig_name = registry.get(t.name).?.zig;

    try common.writeDeprecated(writer, registry, t.deprecated, 0, 3);
    try common.writeDesc(writer, t.description, 0, 3);

    try writer.print("pub const {s} = extern struct {{\n", .{zig_name});
    for (structure.members) |member| {
        try common.writeDesc(writer, member.description, 4, 3);
        try writer.writeAll("    ");
        try common.writeField(writer, member.name);
        try writer.writeAll(": ");
        try common.writeType(writer, registry, member.type);

        switch (initialization) {
            .none => {},
            .undefined => try writer.writeAll(" = undefined"),
            .zero => {
                try writer.writeAll(" = @import(\"std\").mem.zeroes(");
                try common.writeType(writer, registry, member.type);
                try writer.writeAll(")");
            },
        }

        try writer.writeAll(",\n");
    }
    try writer.writeAll("};\n");
}

test "struct member initialization follows the option" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionPropertyInfo", .data = .{ .@"struct" = .{ .members = &.{} } } },
        .{ .name = "GDExtensionTest", .data = .{ .@"struct" = .{ .members = &.{
            .{ .name = "count", .type = "int32_t" },
            .{ .name = "info", .type = "GDExtensionPropertyInfo*" },
        } } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    const cases = [_]struct { mode: Options.MemberInitialization, expected: []const u8 }{
        .{
            .mode = .none,
            .expected =
            \\pub const Test = extern struct {
            \\    count: i32,
            \\    info: ?*PropertyInfo,
            \\};
            \\
            ,
        },
        .{
            .mode = .undefined,
            .expected =
            \\pub const Test = extern struct {
            \\    count: i32 = undefined,
            \\    info: ?*PropertyInfo = undefined,
            \\};
            \\
            ,
        },
        .{
            .mode = .zero,
            .expected =
            \\pub const Test = extern struct {
            \\    count: i32 = @import("std").mem.zeroes(i32),
            \\    info: ?*PropertyInfo = @import("std").mem.zeroes(?*PropertyInfo),
            \\};
            \\
            ,
        },
    };

    for (cases) |case| {
        var aw: Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try emit(&aw.writer, registry, case.mode, types[1]);
        try std.testing.expectEqualStrings(case.expected, aw.writer.buffered());
    }
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../model/InterfaceJson.zig");
const Options = @import("Options.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
