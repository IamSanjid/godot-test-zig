//! Ptrcall slot marshalling through the `godot.abi` facade: canonical slot
//! widths, scalar widening/narrowing, and enum/bitfield int64 transport.
//!
//! Argument/return marshalling is exercised through `readArgument`/`writeReturn`
//! (the engine-facing entry points); `Box` classification and conversions are
//! checked directly, including compile-time width checks.

test "scalar ptrcall slots" {
    var float_slot: f64 = 1.5;
    try std.testing.expectEqual(@as(f32, 1.5), abi.readArgument(f32, @ptrCast(&float_slot)));

    var float_return: f64 = 0;
    abi.writeReturn(f32, @ptrCast(&float_return), 2.5);
    try std.testing.expectEqual(@as(f64, 2.5), float_return);

    var bool_slot: u8 = 1;
    try std.testing.expect(abi.readArgument(bool, @ptrCast(&bool_slot)));

    var narrow_slot: i64 = -7;
    try std.testing.expectEqual(@as(i32, -7), abi.readArgument(i32, @ptrCast(&narrow_slot)));

    var wide_slot: u64 = 1 << 40;
    try std.testing.expectEqual(@as(u64, 1 << 40), abi.readArgument(u64, @ptrCast(&wide_slot)));
    abi.writeReturn(u64, @ptrCast(&wide_slot), 1 << 41);
    try std.testing.expectEqual(@as(u64, 1 << 41), wide_slot);
}

test "enum and bitfield slots are int64" {
    const Mode = enum(u32) { a = 0, b = 1 };
    var enum_slot: i64 = 1;
    try std.testing.expectEqual(Mode.b, abi.readArgument(Mode, @ptrCast(&enum_slot)));

    const Flags = bitpack struct(u32) {
        first: bool = false,
        padding0: u31 = 0,
    };
    const flags: Flags = .{ .first = true };
    var flags_slot: i64 = 0;
    abi.writeReturn(Flags, @ptrCast(&flags_slot), flags);
    try std.testing.expectEqual(@as(i64, 1), flags_slot);
    try std.testing.expectEqual(true, abi.readArgument(Flags, @ptrCast(&flags_slot)).first);
}

test "Box classifies canonical slots" {
    const Plain = extern struct { x: i32 };

    try std.testing.expect(comptime abi.Box(bool).Raw == u8);
    try std.testing.expect(comptime abi.Box(i8).Raw == i64);
    try std.testing.expect(comptime abi.Box(u8).Raw == i64);
    try std.testing.expect(comptime abi.Box(i16).Raw == i64);
    try std.testing.expect(comptime abi.Box(u16).Raw == i64);
    try std.testing.expect(comptime abi.Box(i32).Raw == i64);
    try std.testing.expect(comptime abi.Box(u32).Raw == i64);
    try std.testing.expect(comptime abi.Box(i64).Raw == i64);
    try std.testing.expect(comptime abi.Box(u64).Raw == u64);
    try std.testing.expect(comptime abi.Box(f32).Raw == f64);
    try std.testing.expect(comptime abi.Box(f64).Raw == f64);
    try std.testing.expect(comptime abi.Box(Plain).Raw == Plain);
    try std.testing.expect(comptime abi.Box(?*const anyopaque).Raw == ?*const anyopaque);

    try std.testing.expect(comptime abi.Box(bool).canonical);
    try std.testing.expect(comptime abi.Box(i8).canonical);
    try std.testing.expect(comptime abi.Box(u64).canonical);
    try std.testing.expect(comptime abi.Box(f32).canonical);
    try std.testing.expect(comptime !abi.Box(Plain).canonical);
    try std.testing.expect(comptime !abi.Box(?*anyopaque).canonical);

    try std.testing.expectEqual(@as(u8, 1), comptime abi.Box(bool).widen(true));
    try std.testing.expectEqual(@as(i64, -3), comptime abi.Box(i8).widen(-3));
    try std.testing.expectEqual(@as(u64, 1 << 63), comptime abi.Box(u64).widen(@as(u64, 1) << 63));
    try std.testing.expectEqual(@as(f64, 1.5), comptime abi.Box(f32).widen(1.5));

    try std.testing.expectEqual(true, comptime abi.Box(bool).narrow(1));
    try std.testing.expectEqual(@as(i8, -3), comptime abi.Box(i8).narrow(-3));
    try std.testing.expectEqual(@as(u64, 1 << 63), comptime abi.Box(u64).narrow(@as(u64, 1) << 63));
    try std.testing.expectEqual(@as(f32, 2.5), comptime abi.Box(f32).narrow(2.5));
}

test "Box widens and narrows enums and bitfields" {
    const Mode = enum(u32) { a = 0, b = 1 };
    try std.testing.expect(comptime abi.Box(Mode).Raw == i64);
    try std.testing.expectEqual(@as(i64, 1), comptime abi.Box(Mode).widen(.b));
    try std.testing.expectEqual(Mode.b, comptime abi.Box(Mode).narrow(1));

    const Flags = bitpack struct(u32) {
        first: bool = false,
        padding0: u31 = 0,
    };
    try std.testing.expect(comptime abi.Box(Flags).Raw == i64);
    try std.testing.expectEqual(@as(i64, 1), comptime abi.Box(Flags).widen(.{ .first = true }));
    try std.testing.expectEqual(true, comptime abi.Box(Flags).narrow(1).first);

    const WideFlags = bitpack struct(u64) {
        low: bool = false,
        high: bool = false,
        padding0: u62 = 0,
    };
    const wide: WideFlags = .{ .high = true };
    try std.testing.expect(comptime abi.Box(WideFlags).Raw == i64);
    const wide_slot = comptime abi.Box(WideFlags).widen(wide);
    try std.testing.expectEqual(@as(i64, @bitCast(@as(u64, 1) << 1)), wide_slot);
    try std.testing.expect(comptime abi.Box(WideFlags).narrow(wide_slot).high);
}

const std = @import("std");

const godot = @import("godot");
const abi = godot.abi;
