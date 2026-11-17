//! Canonical Godot GDExtension ptrcall scalar slots and public scalar types.
//!
//! Godot converts every ptrcall value from its C++ type to a canonical slot
//! (`PtrToArg<T>` in `core/variant/method_ptrcall.h`):
//!
//! | API type | C++ type | Canonical slot |
//! |---|---|---|
//! | `int` with any `meta` except `uint64` | `int32_t`, `char32_t`, ... | `i64` |
//! | `int` with `meta:"uint64"` | `uint64_t` | `u64` |
//! | `float` with meta `float` | `float` | `f64` (`PtrToArg<float>::EncodeT` is `double`) |
//! | `float` with meta `double` | `double` | `f64` |
//! | `bool` | `bool` | `u8` (`PtrToArg<bool>::EncodeT` is `uint8_t`) |
//!
//! The public signature type follows the `extension_api.json` `meta` value for
//! API `int`s (`int8` -> `i8`, `uint32` -> `u32`, `char32` -> `u32`, ...), so
//! the binding is naturally typed even though the ptrcall slot stays canonical.
//! The build configuration (`float_*`/`double_*`) only selects `real_t` for the
//! public API and builtin layout; it never selects the ptrcall slot width. So a
//! public `real_t` (`f32` in the default configuration) is cast to an `f64`
//! slot, while an API value with `meta:"double"` is a true `f64` and needs no
//! public conversion.
//!
//! Godot utility functions are C++ `double` even though the API JSON only says
//! `float` and carries no `meta`; `utilityScalar` applies the `meta:"double"`
//! public rule for them while keeping class/builtin API floats on `real_t`.
//!
//! Enums/bitfields keep their existing backing-slot handling; this module only
//! covers the scalar `int`/`float`/`bool` API types, plus the public type rules
//! for API floats. It is shared by the bindgen and codegen emitters. The
//! runtime follows the same rule in `src/godot/abi`.

pub const SlotKind = enum {
    int64,
    uint64,
    float64,
    bool8,
};

pub const Scalar = struct {
    slot: SlotKind,
    public_type: []const u8,
};

pub const Conversion = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Classifies a raw API type as a canonical scalar slot and its public Zig type.
///
/// Returns null for everything that keeps its existing handling: enums,
/// bitfields, builtins, `Variant`, class/native pointers and `void`. `meta` is
/// the `extension_api.json` argument/return metadata, if any.
pub fn scalar(raw: []const u8, meta: ?[]const u8, real_name: []const u8) ?Scalar {
    if (std.mem.eql(u8, raw, "int")) {
        return .{
            .slot = if (isUint64(meta)) .uint64 else .int64,
            .public_type = intPublicTypeName(meta),
        };
    }
    if (std.mem.eql(u8, raw, "bool")) return .{ .slot = .bool8, .public_type = "bool" };
    if (std.mem.eql(u8, raw, "float")) return .{ .slot = .float64, .public_type = floatPublicTypeName(meta, real_name) };
    return null;
}

/// Classifies a raw API type for a Godot utility function.
///
/// Utility functions are C++ `double` but the API JSON only says `float` and
/// carries no `meta`, so utility floats use the `meta:"double"` public rule
/// (`f64`). Everything else follows the normal scalar rule.
pub fn utilityScalar(raw: []const u8, real_name: []const u8) ?Scalar {
    if (std.mem.eql(u8, raw, "float")) return .{ .slot = .float64, .public_type = "f64" };
    return scalar(raw, null, real_name);
}

fn isUint64(meta: ?[]const u8) bool {
    const value = meta orelse return false;
    return std.mem.eql(u8, value, "uint64");
}

/// Public Zig type for an API `int` with the given `meta`.
///
/// The metadata names the original C++ integer type; without metadata (or for
/// an unknown metadata value) the canonical public type is `i64`.
pub fn intPublicTypeName(meta: ?[]const u8) []const u8 {
    const value = meta orelse return "i64";
    if (std.mem.eql(u8, value, "int8")) return "i8";
    if (std.mem.eql(u8, value, "uint8")) return "u8";
    if (std.mem.eql(u8, value, "int16")) return "i16";
    if (std.mem.eql(u8, value, "uint16")) return "u16";
    if (std.mem.eql(u8, value, "int32")) return "i32";
    if (std.mem.eql(u8, value, "uint32")) return "u32";
    if (std.mem.eql(u8, value, "int64")) return "i64";
    if (std.mem.eql(u8, value, "uint64")) return "u64";
    // `char32` is a Unicode scalar value; it travels in the `i64` slot.
    if (std.mem.eql(u8, value, "char32")) return "u32";
    return "i64";
}

/// Public Zig type for an API `float`.
///
/// `meta:"double"` names a true C++ `double`, so the public scalar is `f64` and
/// not the build configuration's `real_t`. Every other float (meta `float` or
/// no meta) follows `real_t`, which stays the public precision.
pub fn floatPublicTypeName(meta: ?[]const u8, real_name: []const u8) []const u8 {
    if (meta) |value| {
        if (std.mem.eql(u8, value, "double")) return "f64";
    }
    return real_name;
}

pub fn slotTypeName(kind: SlotKind) []const u8 {
    return switch (kind) {
        .int64 => "i64",
        .uint64 => "u64",
        .float64 => "f64",
        .bool8 => "u8",
    };
}

/// Conversion from a public argument value to its canonical slot.
///
/// Null means the public value already has the canonical slot type and can be
/// pointed at directly.
pub fn argumentConversion(value: Scalar) ?Conversion {
    return switch (value.slot) {
        .int64 => if (std.mem.eql(u8, value.public_type, "i64"))
            null
        else
            .{ .prefix = "@intCast(", .suffix = ")" },
        .uint64 => if (std.mem.eql(u8, value.public_type, "u64"))
            null
        else
            .{ .prefix = "@intCast(", .suffix = ")" },
        .float64 => if (std.mem.eql(u8, value.public_type, "f64"))
            null
        else
            .{ .prefix = "@floatCast(", .suffix = ")" },
        .bool8 => .{ .prefix = "@intFromBool(", .suffix = ")" },
    };
}

/// Conversion from the canonical return slot back to the public return value.
///
/// Null means the public return value already has the canonical return type.
pub fn returnConversion(value: Scalar) ?Conversion {
    return switch (value.slot) {
        .int64 => if (std.mem.eql(u8, value.public_type, "i64"))
            null
        else
            .{ .prefix = "@intCast(", .suffix = ")" },
        .uint64 => if (std.mem.eql(u8, value.public_type, "u64"))
            null
        else
            .{ .prefix = "@intCast(", .suffix = ")" },
        .float64 => if (std.mem.eql(u8, value.public_type, "f64"))
            null
        else
            .{ .prefix = "@floatCast(", .suffix = ")" },
        .bool8 => .{ .prefix = "(", .suffix = " != 0)" },
    };
}

/// Canonical ptrcall slot type for a packed bitfield.
///
/// Godot encodes every `BitField<T>` through `PtrToArg<BitField<T>>`, whose
/// `EncodeT` is always `int64_t` regardless of the public backing width.
pub fn bitfieldSlotTypeName(_: u8) []const u8 {
    return "i64";
}

/// Emits the canonical slot local for a packed bitfield argument.
pub fn writeBitfieldArgSlot(
    writer: *Io.Writer,
    bits: u8,
    index: usize,
    indent: []const u8,
    source: []const u8,
) !void {
    if (bits > 32) {
        try writer.print("{s}const arg{d}_slot: i64 = @bitCast(@as(u64, @bitCast({s})));\n", .{ indent, index, source });
    } else {
        try writer.print("{s}const arg{d}_slot: i64 = @intCast(@as(u{d}, @bitCast({s})));\n", .{ indent, index, bits, source });
    }
}

/// Emits the canonical result local for a packed bitfield return.
pub fn writeBitfieldResultSlot(writer: *Io.Writer, _: u8, indent: []const u8) !void {
    try writer.print("{s}var result: i64 = undefined;\n", .{indent});
}

/// Converts the canonical result local back to the public bitfield type.
pub fn writeBitfieldReturnSlot(writer: *Io.Writer, bits: u8, indent: []const u8) !void {
    if (bits > 32) {
        try writer.print("{s}return @bitCast(@as(u64, @bitCast(result)));\n", .{indent});
    } else {
        try writer.print("{s}return @bitCast(@as(u{d}, @intCast(result)));\n", .{ indent, bits });
    }
}
/// Writes the canonical slot local for one ptrcall argument, plus its
/// `args[index]` entry. `source` is the already-escaped Zig expression for the
/// public value (argument name, options field, reconstructed default, ...).
///
/// A public value that already has the canonical slot type (an API `int` with
/// no/narrow metadata after conversion, a `uint64` `u64`, a
/// `meta:"double"` `f64`, ...) is pointed at directly. Narrow integers, `real_t`
/// floats and `bool` get an explicit slot local.
pub fn writeArgSlot(
    writer: *Io.Writer,
    value: Scalar,
    index: usize,
    indent: []const u8,
    source: []const u8,
) !void {
    const conversion = argumentConversion(value) orelse {
        try writer.print("{s}args[{d}] = @ptrCast(&{s});\n", .{ indent, index, source });
        return;
    };
    try writer.print("{s}const arg{d}_slot: {s} = {s}{s}{s};\n", .{
        indent, index, slotTypeName(value.slot), conversion.prefix, source, conversion.suffix,
    });
    try writer.print("{s}args[{d}] = @ptrCast(&arg{d}_slot);\n", .{ indent, index, index });
}

/// Writes `<indent>const <name>: <slot> = <conversion>(<source>);` for a value
/// whose canonical slot is passed by pointer outside of the `args` array
/// (operator operands). Returns whether a local was needed.
pub fn writeConvertedSlot(
    writer: *Io.Writer,
    value: Scalar,
    local_name: []const u8,
    indent: []const u8,
    source: []const u8,
) !bool {
    const conversion = argumentConversion(value) orelse return false;
    try writer.print("{s}const {s}: {s} = {s}{s}{s};\n", .{
        indent, local_name, slotTypeName(value.slot), conversion.prefix, source, conversion.suffix,
    });
    return true;
}

/// Writes the canonical return slot local (`var result: <slot> = undefined;`).
///
/// Scalar returns do not need a result initializer: the engine writes the slot
/// before the wrapper reads it.
pub fn writeResultSlot(writer: *Io.Writer, value: Scalar, indent: []const u8) !void {
    try writer.print("{s}var result: {s} = undefined;\n", .{ indent, slotTypeName(value.slot) });
}

/// Writes the return statement converting the canonical slot back to the
/// public return type.
pub fn writeReturnSlot(writer: *Io.Writer, value: Scalar, indent: []const u8) !void {
    try writer.print("{s}return ", .{indent});
    if (returnConversion(value)) |conversion| {
        try writer.print("{s}result{s}", .{ conversion.prefix, conversion.suffix });
    } else {
        try writer.writeAll("result");
    }
    try writer.writeAll(";\n");
}

test "scalar classification and public scalar types" {
    const int_value = scalar("int", null, "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int_value.slot);
    try std.testing.expectEqualStrings("i64", int_value.public_type);

    const int64_value = scalar("int", "int64", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int64_value.slot);
    try std.testing.expectEqualStrings("i64", int64_value.public_type);

    const int8_value = scalar("int", "int8", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int8_value.slot);
    try std.testing.expectEqualStrings("i8", int8_value.public_type);

    const uint8_value = scalar("int", "uint8", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, uint8_value.slot);
    try std.testing.expectEqualStrings("u8", uint8_value.public_type);

    const int16_value = scalar("int", "int16", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int16_value.slot);
    try std.testing.expectEqualStrings("i16", int16_value.public_type);

    const uint16_value = scalar("int", "uint16", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, uint16_value.slot);
    try std.testing.expectEqualStrings("u16", uint16_value.public_type);

    const int32_value = scalar("int", "int32", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int32_value.slot);
    try std.testing.expectEqualStrings("i32", int32_value.public_type);

    const uint32_value = scalar("int", "uint32", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, uint32_value.slot);
    try std.testing.expectEqualStrings("u32", uint32_value.public_type);

    const uint64_value = scalar("int", "uint64", "f32").?;
    try std.testing.expectEqual(SlotKind.uint64, uint64_value.slot);
    try std.testing.expectEqualStrings("u64", uint64_value.public_type);

    const char32_value = scalar("int", "char32", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, char32_value.slot);
    try std.testing.expectEqualStrings("u32", char32_value.public_type);

    try std.testing.expectEqualStrings("i64", intPublicTypeName(null));
    try std.testing.expectEqualStrings("i64", intPublicTypeName(""));
    try std.testing.expectEqualStrings("i64", intPublicTypeName("required"));

    const bool_value = scalar("bool", null, "f32").?;
    try std.testing.expectEqual(SlotKind.bool8, bool_value.slot);
    try std.testing.expectEqualStrings("bool", bool_value.public_type);

    const plain_float = scalar("float", null, "f32").?;
    try std.testing.expectEqual(SlotKind.float64, plain_float.slot);
    try std.testing.expectEqualStrings("f32", plain_float.public_type);

    const meta_float = scalar("float", "float", "f64").?;
    try std.testing.expectEqualStrings("f64", meta_float.public_type);

    const meta_double = scalar("float", "double", "f32").?;
    try std.testing.expectEqual(SlotKind.float64, meta_double.slot);
    try std.testing.expectEqualStrings("f64", meta_double.public_type);

    try std.testing.expectEqualStrings("f64", floatPublicTypeName("double", "f32"));
    try std.testing.expectEqualStrings("f32", floatPublicTypeName("float", "f32"));
    try std.testing.expectEqualStrings("f32", floatPublicTypeName(null, "f32"));
    try std.testing.expectEqualStrings("f64", floatPublicTypeName(null, "f64"));

    try std.testing.expect(scalar("Vector2", null, "f32") == null);
    try std.testing.expect(scalar("enum::Node.Mode", null, "f32") == null);
}

test "utility scalar public types" {
    const sin_value = utilityScalar("float", "f32").?;
    try std.testing.expectEqual(SlotKind.float64, sin_value.slot);
    try std.testing.expectEqualStrings("f64", sin_value.public_type);

    const int_value = utilityScalar("int", "f32").?;
    try std.testing.expectEqual(SlotKind.int64, int_value.slot);
    try std.testing.expectEqualStrings("i64", int_value.public_type);

    try std.testing.expect(utilityScalar("Vector2", "f32") == null);
}

test "slot conversions" {
    try std.testing.expect(argumentConversion(scalar("int", null, "f32").?) == null);
    try std.testing.expect(argumentConversion(scalar("int", "int64", "f32").?) == null);
    try std.testing.expect(argumentConversion(scalar("int", "uint64", "f32").?) == null);
    try std.testing.expect(argumentConversion(scalar("float", "double", "f32").?) == null);
    try std.testing.expect(argumentConversion(scalar("float", null, "f64").?) == null);

    const int32_to_slot = argumentConversion(scalar("int", "int32", "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@intCast(", int32_to_slot.prefix);
    try std.testing.expectEqualStrings(")", int32_to_slot.suffix);

    const char32_to_slot = argumentConversion(scalar("int", "char32", "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@intCast(", char32_to_slot.prefix);

    const float_to_slot = argumentConversion(scalar("float", null, "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@floatCast(", float_to_slot.prefix);
    try std.testing.expectEqualStrings(")", float_to_slot.suffix);

    const bool_to_slot = argumentConversion(scalar("bool", null, "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@intFromBool(", bool_to_slot.prefix);

    try std.testing.expect(returnConversion(scalar("int", "int64", "f32").?) == null);
    try std.testing.expect(returnConversion(scalar("int", "uint64", "f32").?) == null);

    const slot_to_int32 = returnConversion(scalar("int", "int32", "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@intCast(", slot_to_int32.prefix);

    const slot_to_char32 = returnConversion(scalar("int", "char32", "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@intCast(", slot_to_char32.prefix);

    const slot_to_float = returnConversion(scalar("float", null, "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("@floatCast(", slot_to_float.prefix);
    try std.testing.expect(returnConversion(scalar("float", "double", "f32").?) == null);

    const slot_to_bool = returnConversion(scalar("bool", null, "f32").?) orelse return error.MissingConversion;
    try std.testing.expectEqualStrings("(", slot_to_bool.prefix);
    try std.testing.expectEqualStrings(" != 0)", slot_to_bool.suffix);
}

test "argument and return slot emission" {
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    try writeArgSlot(&aw.writer, scalar("float", null, "f32").?, 0, "    ", "p_value");
    try writeArgSlot(&aw.writer, scalar("float", "double", "f32").?, 1, "    ", "p_value");
    try writeArgSlot(&aw.writer, scalar("bool", null, "f32").?, 2, "    ", "p_enabled");
    try writeArgSlot(&aw.writer, scalar("int", null, "f32").?, 3, "    ", "p_count");
    try writeArgSlot(&aw.writer, scalar("int", "int8", "f32").?, 4, "    ", "p_small");
    try writeArgSlot(&aw.writer, scalar("int", "uint64", "f32").?, 5, "    ", "p_id");
    try std.testing.expectEqualStrings(
        \\    const arg0_slot: f64 = @floatCast(p_value);
        \\    args[0] = @ptrCast(&arg0_slot);
        \\    args[1] = @ptrCast(&p_value);
        \\    const arg2_slot: u8 = @intFromBool(p_enabled);
        \\    args[2] = @ptrCast(&arg2_slot);
        \\    args[3] = @ptrCast(&p_count);
        \\    const arg4_slot: i64 = @intCast(p_small);
        \\    args[4] = @ptrCast(&arg4_slot);
        \\    args[5] = @ptrCast(&p_id);
        \\
    , aw.writer.buffered());

    var rw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer rw.deinit();

    try writeResultSlot(&rw.writer, scalar("float", null, "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("float", null, "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("float", "double", "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("float", "double", "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("bool", null, "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("bool", null, "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("int", null, "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("int", null, "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("int", "int8", "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("int", "int8", "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("int", "char32", "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("int", "char32", "f32").?, "    ");
    try writeResultSlot(&rw.writer, scalar("int", "uint64", "f32").?, "    ");
    try writeReturnSlot(&rw.writer, scalar("int", "uint64", "f32").?, "    ");
    try std.testing.expectEqualStrings(
        \\    var result: f64 = undefined;
        \\    return @floatCast(result);
        \\    var result: f64 = undefined;
        \\    return result;
        \\    var result: u8 = undefined;
        \\    return (result != 0);
        \\    var result: i64 = undefined;
        \\    return result;
        \\    var result: i64 = undefined;
        \\    return @intCast(result);
        \\    var result: i64 = undefined;
        \\    return @intCast(result);
        \\    var result: u64 = undefined;
        \\    return result;
        \\
    , rw.writer.buffered());
}

const std = @import("std");
const Io = std.Io;
