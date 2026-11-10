//! Shared enum/bitfield emission for builtins, classes, and global enums.

pub fn write(writer: *Io.Writer, arena: Allocator, global_enum: ExtensionApiJson.GlobalEnum, indent: usize) !void {
    const prefix_len = enum_utils.commonPrefixLen(global_enum.values);
    if (global_enum.is_bitfield) {
        try writeBitfield(writer, arena, global_enum, prefix_len, indent);
    } else {
        try writePlain(writer, arena, global_enum, prefix_len, indent);
    }
}

fn writePlain(
    writer: *Io.Writer,
    arena: Allocator,
    global_enum: ExtensionApiJson.GlobalEnum,
    prefix_len: usize,
    indent: usize,
) !void {
    var negative = false;
    for (global_enum.values) |value| {
        if (value.value < 0) negative = true;
    }

    try writeIndent(writer, indent);
    try writer.writeAll("pub const ");
    try common.writeIdent(writer, .pascal, global_enum.name);
    try writer.print(" = enum({s}) {{\n", .{if (negative) "i32" else "u32"});

    var alias_count: usize = 0;
    for (global_enum.values, 0..) |value, index| {
        if (isDuplicate(global_enum.values, index)) {
            alias_count += 1;
            continue;
        }
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try common.writeIdent(writer, .snake, enum_utils.variantName(value.name, prefix_len));
        try writer.print(" = {d},\n", .{value.value});
    }

    if (alias_count != 0) try writer.writeAll("\n");
    for (global_enum.values, 0..) |value, index| {
        if (!isDuplicate(global_enum.values, index)) continue;
        try docs.write(writer, arena, value.description, indent + 4, "///");
        try writeIndent(writer, indent + 4);
        try writer.writeAll("pub const ");
        try common.writeIdent(writer, .snake, enum_utils.variantName(value.name, prefix_len));
        try writer.print(": @This() = @fromBackingInt(@intCast({d}));\n", .{value.value});
    }

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

    try writeIndent(writer, indent);
    try writer.writeAll("pub const ");
    try common.writeIdent(writer, .pascal, global_enum.name);
    try writer.writeAll(" = packed struct(u32) {\n");

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
        try common.writeIdent(writer, .snake, enum_utils.variantName(value.name, prefix_len));
        try writer.writeAll(": bool = false,\n");
        next = @as(u7, bit.pos) + 1;
    }
    if (next < 32) {
        try writeIndent(writer, indent + 4);
        try writer.print("_pad{d}: u{d} = 0,\n", .{ pad_index, 32 - next });
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
        try common.writeIdent(writer, .snake, enum_utils.variantName(value.name, prefix_len));
        try writer.print(": @This() = @bitCast(@as(u32, {d}));\n", .{value.value});
    }

    try writeIndent(writer, indent);
    try writer.writeAll("};\n");
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const common = @import("common.zig");
const docs = @import("docs.zig");
const enum_utils = @import("enum_utils.zig");
const ExtensionApiJson = @import("../ExtensionApiJson.zig");
