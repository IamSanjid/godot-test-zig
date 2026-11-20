//! Canonical ptrcall marshalling: ints/enums/bitfields -> `i64` (`u64` for
//! unsigned 64-bit), floats -> `f64`, bool -> `u8`; other types keep their
//! layout. `RefCounted` values travel as `Ref<T>`.

/// Canonical slot conversion for `T`: `Raw`, `canonical`, `widen`, `narrow`.
pub fn Box(comptime T: type) type {
    return struct {
        pub const Raw = RawType(T);
        pub const canonical = isCanonical(T);

        pub fn widen(value: T) Raw {
            switch (@typeInfo(T)) {
                .bool => return @intFromBool(value),
                .int => return @intCast(value),
                .float => return @floatCast(value),
                .@"enum" => |info| return Box(info.tag_type).widen(@backingInt(value)),
                .@"struct" => |info| {
                    // `backing_integer` is only set for `bitpack struct`s.
                    const Backing = info.backing_integer orelse return value;
                    const bits: Backing = @bitCast(value);
                    // Packed bitfields always travel in the `i64` slot.
                    return rawAsI64(Box(Backing).widen(bits));
                },
                else => return value,
            }
        }

        pub fn narrow(raw: Raw) T {
            switch (@typeInfo(T)) {
                .bool => return raw != 0,
                .int => return i64AsPublic(T, raw),
                .float => return @floatCast(raw),
                .@"enum" => |info| return @fromBackingInt(Box(info.tag_type).narrow(raw)),
                .@"struct" => |info| {
                    const Backing = info.backing_integer orelse return raw;
                    const back = Box(Backing).narrow(i64AsRaw(RawType(Backing), raw));
                    return @bitCast(back);
                },
                else => return raw,
            }
        }
    };
}

/// Canonical slot/storage type for every `T` (see `Box`).
fn RawType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .bool => u8,
        .int => |info| blk: {
            if (info.bits > 64) {
                @compileError("canonical ABI slots do not support integers wider than 64 bits: " ++ @typeName(T));
            }
            break :blk if (info.bits == 64 and info.signedness == .unsigned) u64 else i64;
        },
        .float => f64,
        .@"enum" => |info| RawType(info.tag_type),
        .@"struct" => |info| blk: {
            const Backing = info.backing_integer orelse break :blk T;
            if (@bitSizeOf(Backing) > 64) {
                @compileError("canonical ABI slots do not support bitfields wider than 64 bits: " ++ @typeName(T));
            }
            break :blk i64;
        },
        else => T,
    };
}

/// Whether `T` is transported at a canonical scalar width.
fn isCanonical(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => true,
        .@"struct" => |info| info.backing_integer != null,
        else => false,
    };
}

/// Converts the always-`i64` bitfield slot back to `Raw` (which can be `u64`
/// for 64-bit unsigned backings).
fn i64AsRaw(comptime Raw: type, raw: i64) Raw {
    return if (comptime Raw == u64) @bitCast(raw) else @intCast(raw);
}

/// Converts a canonical integer slot value to the public integer type.
fn i64AsPublic(comptime Int: type, raw: RawType(Int)) Int {
    return if (comptime RawType(Int) == u64) @bitCast(raw) else @intCast(raw);
}

/// Fits a canonical raw integer into the always-`i64` bitfield slot.
fn rawAsI64(raw: anytype) i64 {
    return if (comptime @TypeOf(raw) == u64) @bitCast(raw) else @intCast(raw);
}

/// Reads one ptrcall argument slot as `T`.
///
/// The engine passes a pointer to a canonical slot for scalars and a pointer to
/// the declared value for builtins/pointers/optionals.
pub fn readArgument(comptime T: type, raw_p_arg: ?*const anyopaque) T {
    const B = Box(T);
    const p_arg: *const anyopaque = @ptrCast(raw_p_arg);
    return B.narrow(@as(*const B.Raw, @ptrCast(@alignCast(p_arg))).*);
}

/// Writes `value` into one ptrcall return slot as `T`.
///
/// This only performs the ABI write. Releasing prior non-trivial storage is the
/// caller's responsibility because that policy differs between varcall and
/// direct ptrcall paths.
pub fn writeReturn(comptime T: type, raw_p_ret: ?*anyopaque, value: T) void {
    const B = Box(T);
    const p_ret: *anyopaque = @ptrCast(raw_p_ret);
    @as(*B.Raw, @ptrCast(@alignCast(p_ret))).* = B.widen(value);
}

test "scalar ptrcall slots" {
    const std = @import("std");
    var float_slot: f64 = 1.5;
    try std.testing.expectEqual(@as(f32, 1.5), readArgument(f32, @ptrCast(&float_slot)));

    var float_return: f64 = 0;
    writeReturn(f32, @ptrCast(&float_return), 2.5);
    try std.testing.expectEqual(@as(f64, 2.5), float_return);

    var bool_slot: u8 = 1;
    try std.testing.expect(readArgument(bool, @ptrCast(&bool_slot)));

    var narrow_slot: i64 = -7;
    try std.testing.expectEqual(@as(i32, -7), readArgument(i32, @ptrCast(&narrow_slot)));

    var wide_slot: u64 = 1 << 40;
    try std.testing.expectEqual(@as(u64, 1 << 40), readArgument(u64, @ptrCast(&wide_slot)));
    writeReturn(u64, @ptrCast(&wide_slot), 1 << 41);
    try std.testing.expectEqual(@as(u64, 1 << 41), wide_slot);
}

test "enum and bitfield slots are int64" {
    const std = @import("std");
    const Mode = enum(u32) { a = 0, b = 1 };
    var enum_slot: i64 = 1;
    try std.testing.expectEqual(Mode.b, readArgument(Mode, @ptrCast(&enum_slot)));

    const Flags = bitpack struct(u32) {
        first: bool = false,
        padding0: u31 = 0,
    };
    const flags: Flags = .{ .first = true };
    var flags_slot: i64 = 0;
    writeReturn(Flags, @ptrCast(&flags_slot), flags);
    try std.testing.expectEqual(@as(i64, 1), flags_slot);
    try std.testing.expectEqual(true, readArgument(Flags, @ptrCast(&flags_slot)).first);
}

test "Box classifies canonical slots" {
    const std = @import("std");

    const Plain = extern struct { x: i32 };

    try std.testing.expect(comptime Box(bool).Raw == u8);
    try std.testing.expect(comptime Box(i8).Raw == i64);
    try std.testing.expect(comptime Box(u8).Raw == i64);
    try std.testing.expect(comptime Box(i16).Raw == i64);
    try std.testing.expect(comptime Box(u16).Raw == i64);
    try std.testing.expect(comptime Box(i32).Raw == i64);
    try std.testing.expect(comptime Box(u32).Raw == i64);
    try std.testing.expect(comptime Box(i64).Raw == i64);
    try std.testing.expect(comptime Box(u64).Raw == u64);
    try std.testing.expect(comptime Box(f32).Raw == f64);
    try std.testing.expect(comptime Box(f64).Raw == f64);
    try std.testing.expect(comptime Box(Plain).Raw == Plain);
    try std.testing.expect(comptime Box(?*const anyopaque).Raw == ?*const anyopaque);

    try std.testing.expect(comptime Box(bool).canonical);
    try std.testing.expect(comptime Box(i8).canonical);
    try std.testing.expect(comptime Box(u64).canonical);
    try std.testing.expect(comptime Box(f32).canonical);
    try std.testing.expect(comptime !Box(Plain).canonical);
    try std.testing.expect(comptime !Box(?*anyopaque).canonical);

    try std.testing.expectEqual(@as(u8, 1), comptime Box(bool).widen(true));
    try std.testing.expectEqual(@as(i64, -3), comptime Box(i8).widen(-3));
    try std.testing.expectEqual(@as(u64, 1 << 63), comptime Box(u64).widen(@as(u64, 1) << 63));
    try std.testing.expectEqual(@as(f64, 1.5), comptime Box(f32).widen(1.5));

    try std.testing.expectEqual(true, comptime Box(bool).narrow(1));
    try std.testing.expectEqual(@as(i8, -3), comptime Box(i8).narrow(-3));
    try std.testing.expectEqual(@as(u64, 1 << 63), comptime Box(u64).narrow(@as(u64, 1) << 63));
    try std.testing.expectEqual(@as(f32, 2.5), comptime Box(f32).narrow(2.5));
}

test "Box widens and narrows enums and bitfields" {
    const std = @import("std");

    const Mode = enum(u32) { a = 0, b = 1 };
    try std.testing.expect(comptime Box(Mode).Raw == i64);
    try std.testing.expectEqual(@as(i64, 1), comptime Box(Mode).widen(.b));
    try std.testing.expectEqual(Mode.b, comptime Box(Mode).narrow(1));

    const Flags = bitpack struct(u32) {
        first: bool = false,
        padding0: u31 = 0,
    };
    try std.testing.expect(comptime Box(Flags).Raw == i64);
    try std.testing.expectEqual(@as(i64, 1), comptime Box(Flags).widen(.{ .first = true }));
    try std.testing.expectEqual(true, comptime Box(Flags).narrow(1).first);

    const WideFlags = bitpack struct(u64) {
        low: bool = false,
        high: bool = false,
        padding0: u62 = 0,
    };
    const wide: WideFlags = .{ .high = true };
    try std.testing.expect(comptime Box(WideFlags).Raw == i64);
    const wide_slot = comptime Box(WideFlags).widen(wide);
    try std.testing.expectEqual(@as(i64, @bitCast(@as(u64, 1) << 1)), wide_slot);
    try std.testing.expect(comptime Box(WideFlags).narrow(wide_slot).high);
}
