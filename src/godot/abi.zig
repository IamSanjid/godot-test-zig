//! Canonical Godot ptrcall marshalling.
//!
//! Godot does not transport scalar values at their public Zig width:
//!
//! - integers, enums and packed flag structs -> `i64` (or `u64` for u64-backed)
//! - `f32` / `f64` -> `f64`
//! - `bool` -> `u8`
//!
//! Everything else keeps its declared layout and is read/written directly.
//! This is the same rule for virtual callbacks and any future ptrcall-facing
//! code. It is type-driven: there is no per-value slot enum or generated slot
//! metadata.
//!
//! `RefCounted` values are the exception: they travel as `Ref<T>` storage and
//! need `ref_get_object` / `ref_set_object`. That conversion belongs to the
//! extension-method/virtual layer, not here.

/// Reads one ptrcall argument slot as `T`.
///
/// The engine passes a pointer to a canonical slot for scalars and a pointer to
/// the declared value for builtins/pointers/optionals.
pub fn readArgument(comptime T: type, raw_p_arg: ?*const anyopaque) T {
    const p_arg: *const anyopaque = @ptrCast(raw_p_arg);
    return switch (@typeInfo(T)) {
        .bool => @as(*const u8, @ptrCast(p_arg)).* != 0,
        .int => @intCast(readIntSlot(T, p_arg)),
        .float => @floatCast(@as(*const f64, @ptrCast(@alignCast(p_arg))).*),
        .@"enum" => |info| @fromBackingInt(@intCast(backingFromInt(
            info.tag_type,
            @intCast(readIntSlot(i64, p_arg)),
        ))),
        .@"struct" => |info| blk: {
            const Backing = info.backing_integer orelse
                break :blk @as(*const T, @ptrCast(@alignCast(p_arg))).*;
            break :blk @bitCast(backingFromInt(Backing, @intCast(readIntSlot(i64, p_arg))));
        },
        else => @as(*const T, @ptrCast(@alignCast(p_arg))).*,
    };
}

/// Writes `value` into one ptrcall return slot as `T`.
///
/// This only performs the ABI write. Releasing prior non-trivial storage is the
/// caller's responsibility because that policy differs between varcall and
/// direct ptrcall paths.
pub fn writeReturn(comptime T: type, raw_p_ret: ?*anyopaque, value: T) void {
    const p_ret: *anyopaque = @ptrCast(raw_p_ret);
    switch (@typeInfo(T)) {
        .bool => @as(*u8, @ptrCast(p_ret)).* = @intFromBool(value),
        .int => writeIntSlot(T, p_ret, value),
        .float => @as(*f64, @ptrCast(@alignCast(p_ret))).* = @floatCast(value),
        .@"enum" => |info| writeIntSlot(info.tag_type, p_ret, @backingInt(value)),
        .@"struct" => |info| {
            const Backing = info.backing_integer orelse {
                @as(*T, @ptrCast(@alignCast(p_ret))).* = value;
                return;
            };
            writeIntSlot(i64, p_ret, intFromBacking(Backing, @as(Backing, @bitCast(value))));
        },
        else => @as(*T, @ptrCast(@alignCast(p_ret))).* = value,
    }
}

fn readIntSlot(comptime Int: type, p_arg: *const anyopaque) i128 {
    const info = @typeInfo(Int).int;
    if (comptime info.bits > 64) @compileError("ptrcall does not support integers wider than 64 bits");
    if (comptime isU64Like(Int)) {
        return @as(*const u64, @ptrCast(@alignCast(p_arg))).*;
    }
    return @as(*const i64, @ptrCast(@alignCast(p_arg))).*;
}

fn writeIntSlot(comptime Int: type, p_ret: *anyopaque, value: anytype) void {
    const info = @typeInfo(Int).int;
    if (comptime info.bits > 64) @compileError("ptrcall does not support integers wider than 64 bits");
    if (comptime isU64Like(Int)) {
        @as(*u64, @ptrCast(@alignCast(p_ret))).* = @intCast(value);
    } else {
        @as(*i64, @ptrCast(@alignCast(p_ret))).* = @intCast(value);
    }
}

fn backingFromInt(comptime Backing: type, raw: i64) Backing {
    if (comptime @bitSizeOf(Backing) == 64) return @bitCast(raw);
    return @intCast(raw);
}

fn intFromBacking(comptime Backing: type, value: Backing) i64 {
    if (comptime @bitSizeOf(Backing) == 64) return @bitCast(value);
    return @intCast(value);
}

fn isU64Like(comptime Int: type) bool {
    const info = @typeInfo(Int).int;
    return info.bits == 64 and info.signedness == .unsigned;
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
        _pad0: u31 = 0,
    };
    const flags: Flags = .{ .first = true };
    var flags_slot: i64 = 0;
    writeReturn(Flags, @ptrCast(&flags_slot), flags);
    try std.testing.expectEqual(@as(i64, 1), flags_slot);
    try std.testing.expectEqual(true, readArgument(Flags, @ptrCast(&flags_slot)).first);
}
