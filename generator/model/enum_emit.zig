//! Shared enum/bitfield emission for builtins, classes, and global enums.

pub fn write(writer: *Io.Writer, arena: Allocator, global_enum: ExtensionApiJson.GlobalEnum, indent: usize) !void {
    try writeWithExtra(writer, arena, global_enum, indent, "");
}

/// Like `write`, but appends `extra_code` as raw declarations inside the
/// generated enum/bitfield declaration. Custom `extend` sections use this to
/// grow enum bodies without enum-specific custom grammar.
pub fn writeWithExtra(
    writer: *Io.Writer,
    arena: Allocator,
    global_enum: ExtensionApiJson.GlobalEnum,
    indent: usize,
    extra_code: []const u8,
) !void {
    const prefix_len = enum_utils.commonPrefixLen(global_enum.values);
    if (global_enum.is_bitfield) {
        try writeBitfield(writer, arena, global_enum, prefix_len, indent, extra_code);
    } else {
        try writePlain(writer, arena, global_enum, prefix_len, indent, extra_code);
    }
}

/// Generated Zig type name of an enum. Custom `extend` sections target it.
pub fn zigTypeName(arena: Allocator, global_enum: ExtensionApiJson.GlobalEnum) ![]const u8 {
    return names.pascal(arena, global_enum.name);
}

fn writePlain(
    writer: *Io.Writer,
    arena: Allocator,
    global_enum: ExtensionApiJson.GlobalEnum,
    prefix_len: usize,
    indent: usize,
    extra_code: []const u8,
) !void {
    var negative = false;
    for (global_enum.values) |value| {
        if (value.value < 0) negative = true;
    }

    try writeIndent(writer, indent);
    try writer.writeAll("pub const ");
    try names.writeTypeName(writer, global_enum.name);
    try writer.print(" = enum({s}) {{\n", .{if (negative) "i32" else "u32"});

    var alias_count: usize = 0;
    for (global_enum.values, 0..) |value, index| {
        if (isDuplicate(global_enum.values, index)) {
            alias_count += 1;
            continue;
        }
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try names.writeConstant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.print(" = {d},\n", .{value.value});
    }

    if (alias_count != 0) try writer.writeAll("\n");
    for (global_enum.values, 0..) |value, index| {
        if (!isDuplicate(global_enum.values, index)) continue;
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try writer.writeAll("pub const ");
        try names.writeConstant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.print(": @This() = @fromBackingInt(@intCast({d}));\n", .{value.value});
    }

    try writeExtra(writer, extra_code, indent);
    try writeIndent(writer, indent);
    try writer.writeAll("};\n");
}

const Bit = struct { pos: u6, index: usize };

fn writeBitfield(
    writer: *Io.Writer,
    arena: Allocator,
    global_enum: ExtensionApiJson.GlobalEnum,
    prefix_len: usize,
    indent: usize,
    extra_code: []const u8,
) !void {
    var bits: [64]Bit = undefined;
    var bit_count: usize = 0;
    var seen: u64 = 0;
    var has_alias = false;

    for (global_enum.values, 0..) |value, index| {
        if (value.value < 0) return error.NegativeBitfieldValue;
        const unsigned: u64 = @intCast(value.value);
        if (unsigned != 0 and std.math.isPowerOfTwo(unsigned) and (seen & unsigned) == 0) {
            bits[bit_count] = .{ .pos = @intCast(@ctz(unsigned)), .index = index };
            seen |= unsigned;
            bit_count += 1;
        } else {
            has_alias = true;
        }
    }
    std.mem.sort(Bit, bits[0..bit_count], {}, struct {
        fn lessThan(_: void, a: Bit, b: Bit) bool {
            return a.pos < b.pos;
        }
    }.lessThan);

    var backing_bits: u7 = 32;
    if (bit_count != 0 and bits[bit_count - 1].pos >= 32) backing_bits = 64;

    try writeIndent(writer, indent);
    try writer.writeAll("pub const ");
    try names.writeTypeName(writer, global_enum.name);
    try writer.print(" = bitpack struct(u{d}) {{\n", .{backing_bits});

    var next: u7 = 0;
    var pad_index: usize = 0;
    for (bits[0..bit_count]) |bit| {
        if (bit.pos > next) {
            try writeIndent(writer, indent + 4);
            try writer.print("_pad{d}: u{d} = 0,\n", .{ pad_index, bit.pos - next });
            pad_index += 1;
        }
        const value = global_enum.values[bit.index];
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try names.writeConstant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.writeAll(": bool = false,\n");
        next = @as(u7, bit.pos) + 1;
    }
    if (next < backing_bits) {
        try writeIndent(writer, indent + 4);
        try writer.print("_pad{d}: u{d} = 0,\n", .{ pad_index, backing_bits - next });
    }

    if (has_alias) try writer.writeAll("\n");
    var alias_seen: u64 = 0;
    for (global_enum.values) |value| {
        const unsigned: u64 = @intCast(value.value);
        const is_field = unsigned != 0 and std.math.isPowerOfTwo(unsigned) and (alias_seen & unsigned) == 0;
        if (is_field) {
            alias_seen |= unsigned;
            continue;
        }
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try writer.writeAll("pub const ");
        try names.writeConstant(writer, enum_utils.variantName(value.name, prefix_len));
        try writer.print(": @This() = @bitCast(@as(u{d}, {d}));\n", .{ backing_bits, value.value });
    }

    try writeExtra(writer, extra_code, indent);
    try writeIndent(writer, indent);
    try writer.writeAll("};\n");
}

/// Writes extension declarations at body indentation, separated from the
/// generated variants/constants by one blank line.
fn writeExtra(writer: *Io.Writer, extra_code: []const u8, indent: usize) !void {
    if (extra_code.len == 0) return;
    try writer.writeAll("\n");
    try custom.writeIndented(writer, extra_code, indent + 4);
}

fn writeIndent(writer: *Io.Writer, indent: usize) !void {
    for (0..indent) |_| try writer.writeByte(' ');
}

fn isDuplicate(values: []const ExtensionApiJson.GlobalEnumValue, index: usize) bool {
    for (values[0..index]) |previous| {
        if (previous.value == values[index].value) return true;
    }
    return false;
}

test "bitfield selects a backing integer wide enough for its values" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const values = [_]ExtensionApiJson.GlobalEnumValue{
        .{ .name = "FLAG_LOW", .value = 1 },
        .{ .name = "FLAG_HIGH", .value = 1 << 35 },
        .{ .name = "MASK", .value = 7 },
    };
    const global = ExtensionApiJson.GlobalEnum{
        .name = "Flags",
        .is_bitfield = true,
        .values = &values,
    };

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try write(&aw.writer, arena, global, 0);
    const output = aw.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "bitpack struct(u64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_pad0: u34") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "@as(u64, 7)") != null);
}

test "extension code is inserted before the closing brace" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const values = [_]ExtensionApiJson.GlobalEnumValue{
        .{ .name = "FLAG_A", .value = 1 },
        .{ .name = "FLAG_B", .value = 2 },
    };
    const global = ExtensionApiJson.GlobalEnum{
        .name = "Flags",
        .is_bitfield = true,
        .values = &values,
    };

    const extra =
        \\/// Preset combination.
        \\pub const exported: @This() = .{ .flag_a = true };
        \\
    ;

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeWithExtra(&aw.writer, arena, global, 0, extra);
    const output = aw.writer.buffered();

    try std.testing.expect(std.mem.endsWith(u8, output,
        \\    /// Preset combination.
        \\    pub const exported: @This() = .{ .flag_a = true };
        \\};
        \\
    ));
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const names = @import("names.zig");
const naming = @import("naming");
const docs = @import("docs.zig");
const custom = @import("custom.zig");
const enum_utils = @import("enum_utils.zig");
const ExtensionApiJson = @import("ExtensionApiJson.zig");
