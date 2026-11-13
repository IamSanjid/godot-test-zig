//! Emitters for the two enum flavors used by the GDExtension interface:
//! regular enums (a Zig enum backed by the translated C enum) and bitfields
//! (a bitpack struct with one field per flag).

/// Bitfields are emitted as `bitpack struct(gdi.<name>)`. The final padding is
/// expressed with `@bitSizeOf` so it follows the translated C backing type
/// instead of assuming a host/target integer width.
pub fn emit(arena: Allocator, writer: *Io.Writer, registry: Registry, t: InterfaceJson.TypeDecl) !void {
    std.debug.assert(t.data == .@"enum");
    const e = t.data.@"enum";
    const zig_name = registry.get(t.name).?.zig;

    try common.writeDeprecated(writer, registry, t.deprecated, 0, 3);
    try common.writeDesc(writer, t.description, 0, 3);

    if (e.is_bitfield) {
        try emitBitfield(arena, writer, zig_name, t.name, e);
    } else {
        try emitPlain(writer, zig_name, t.name, e);
    }
}

fn emitPlain(writer: *Io.Writer, zig_name: []const u8, raw_name: []const u8, e: InterfaceJson.EnumType) !void {
    const prefix_len = enum_utils.commonPrefixLen(e.values);
    for (e.values) |value| {
        if (value.value < 0) {
            std.log.err("enum {s}: negative value for {s}", .{ raw_name, value.name });
            return error.NegativeEnumValue;
        }
    }

    try writer.print("pub const {s} = enum(gdi.{s}) {{\n", .{ zig_name, raw_name });

    var alias_count: usize = 0;
    for (e.values, 0..) |value, index| {
        if (isDuplicate(e.values, index)) {
            alias_count += 1;
            continue;
        }

        const variant = enum_utils.variantName(value.name, prefix_len);
        try common.writeDesc(writer, value.description, 4, 3);
        try writer.writeAll("    ");
        try common.writeEnumVariant(writer, variant);
        try writer.print(" = {d},\n", .{value.value});
    }

    if (alias_count != 0) try writer.writeAll("\n");
    for (e.values, 0..) |value, index| {
        if (!isDuplicate(e.values, index)) continue;

        const variant = enum_utils.variantName(value.name, prefix_len);
        try common.writeDesc(writer, value.description, 4, 3);
        try writer.writeAll("    pub const ");
        try common.writeEnumVariant(writer, variant);
        try writer.print(": @This() = @fromBackingInt(@intCast({d}));\n", .{value.value});
    }

    try writer.writeAll("};\n");
}

const Bit = struct {
    pos: u6,
    /// Index into `EnumType.values`; keeps the original description/name
    /// without copying either.
    index: usize,
};

fn emitBitfield(
    arena: Allocator,
    writer: *Io.Writer,
    zig_name: []const u8,
    raw_name: []const u8,
    e: InterfaceJson.EnumType,
) !void {
    const prefix_len = enum_utils.commonPrefixLen(e.values);

    const bits = try arena.alloc(Bit, e.values.len);
    defer arena.free(bits);

    var bit_count: usize = 0;
    var seen: u64 = 0;
    var has_alias = false;
    for (e.values, 0..) |value, index| {
        if (value.value < 0) {
            std.log.err("bitfield {s}: negative value for {s}", .{ raw_name, value.name });
            return error.NegativeBitfieldValue;
        }
        const unsigned: u64 = @intCast(value.value);
        if (unsigned != 0 and std.math.isPowerOfTwo(unsigned) and (seen & unsigned) == 0) {
            const pos: u6 = @intCast(@ctz(unsigned));
            seen |= unsigned;
            bits[bit_count] = .{ .pos = pos, .index = index };
            bit_count += 1;
        } else {
            has_alias = true;
        }
    }
    std.mem.sort(Bit, bits[0..bit_count], {}, bitLessThan);

    try writer.print("pub const {s} = bitpack struct(gdi.{s}) {{\n", .{ zig_name, raw_name });

    // Fill gaps between flags with padding, then pad out to the backing
    // integer's width (Zig requires the fields to cover it exactly).
    var next: u7 = 0;
    var pad_index: usize = 0;
    for (bits[0..bit_count]) |bit| {
        const value = e.values[bit.index];
        if (bit.pos > next) {
            try writer.print("    _pad{d}: u{d} = 0,\n", .{ pad_index, bit.pos - next });
            pad_index += 1;
        }
        try common.writeDesc(writer, value.description, 4, 3);
        try writer.writeAll("    ");
        try common.writeEnumVariant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.writeAll(": bool = false,\n");
        next = @as(u7, bit.pos) + 1;
    }
    if (next < 64) {
        try writer.print("    _pad{d}: @Int(.unsigned, @bitSizeOf(gdi.{s}) - {d}) = 0,\n", .{ pad_index, raw_name, next });
    }

    // Everything that is not a single, previously unclaimed bit is exposed as
    // a constant that bit-casts the original C enum value.
    if (has_alias) try writer.writeAll("\n");
    var alias_seen: u64 = 0;
    for (e.values) |value| {
        const unsigned: u64 = @intCast(value.value);
        const is_field = unsigned != 0 and std.math.isPowerOfTwo(unsigned) and (alias_seen & unsigned) == 0;
        if (is_field) {
            alias_seen |= unsigned;
            continue;
        }

        try common.writeDesc(writer, value.description, 4, 3);
        try writer.writeAll("    pub const ");
        try common.writeEnumVariant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.print(": @This() = @bitCast(gdi.{s});\n", .{value.name});
    }

    try writer.writeAll("};\n");
}

fn bitLessThan(_: void, a: Bit, b: Bit) bool {
    return a.pos < b.pos;
}

fn isDuplicate(values: []const InterfaceJson.EnumValue, index: usize) bool {
    for (values[0..index]) |previous| {
        if (previous.value == values[index].value) return true;
    }
    return false;
}

test "plain enums keep aliases for duplicate values" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const values = [_]InterfaceJson.EnumValue{
        .{ .name = "GDEXTENSION_CALL_OK", .value = 0 },
        .{ .name = "GDEXTENSION_CALL_ERROR_INVALID_METHOD", .value = 1, .description = &.{"Bad method."} },
        .{ .name = "GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT", .value = 2 },
        .{ .name = "GDEXTENSION_CALL_ERROR_ALIAS", .value = 2 },
    };
    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionCallErrorType", .data = .{ .@"enum" = .{ .values = &values } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emit(arena_state.allocator(), &aw.writer, registry, types[0]);

    try std.testing.expectEqualStrings(
        \\pub const CallErrorType = enum(gdi.GDExtensionCallErrorType) {
        \\    ok = 0,
        \\    /// Bad method.
        \\    invalid_method = 1,
        \\    invalid_argument = 2,
        \\
        \\    pub const alias: @This() = @fromBackingInt(@intCast(2));
        \\};
        \\
    , aw.writer.buffered());
}

test "bitfields pad gaps and expose aliases" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const values = [_]InterfaceJson.EnumValue{
        .{ .name = "GDEXTENSION_METHOD_FLAG_NORMAL", .value = 1 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_EDITOR", .value = 2 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_CONST", .value = 4 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_VIRTUAL", .value = 8 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_VARARG", .value = 16 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_STATIC", .value = 32 },
        .{ .name = "GDEXTENSION_METHOD_FLAG_VIRTUAL_REQUIRED", .value = 128 },
        .{ .name = "GDEXTENSION_METHOD_FLAGS_DEFAULT", .value = 1 },
    };
    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionClassMethodFlags", .data = .{ .@"enum" = .{ .is_bitfield = true, .values = &values } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try emit(arena_state.allocator(), &aw.writer, registry, types[0]);

    try std.testing.expectEqualStrings(
        \\pub const ClassMethodFlags = bitpack struct(gdi.GDExtensionClassMethodFlags) {
        \\    normal: bool = false,
        \\    editor: bool = false,
        \\    @"const": bool = false,
        \\    virtual: bool = false,
        \\    vararg: bool = false,
        \\    static: bool = false,
        \\    _pad0: u1 = 0,
        \\    virtual_required: bool = false,
        \\    _pad1: @Int(.unsigned, @bitSizeOf(gdi.GDExtensionClassMethodFlags) - 8) = 0,
        \\
        \\    pub const default: @This() = @bitCast(gdi.GDEXTENSION_METHOD_FLAGS_DEFAULT);
        \\};
        \\
    , aw.writer.buffered());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const InterfaceJson = @import("../model/InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
const enum_utils = @import("../model/enum_utils.zig");
