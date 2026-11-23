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
