// @section artifact Data
/// Opaque engine-private packed-array header.
///
/// This type only gives `Data.packed_*` a distinct typed pointer instead of
/// `?*anyopaque`. Nothing here is constructed, mutated, dereferenced or treated
/// as the engine's layout; packed arrays only move through the engine Variant
/// constructors/destructors.
fn PackedArrayRef(comptime T: type) type {
    _ = T;
    return opaque {};
}

pub const Data = extern union {
    aabb: *AABB,
    array: Array,
    basis: *Basis,
    bool: bool,
    callable: Callable,
    color: Color,
    dictionary: Dictionary,
    // Engine layout fact: `Variant::_data._float` is C++ `double` in every
    // build configuration. This field does not determine the Variant size;
    // `_mem[sizeof(real_t) * 4]` and the generated builtin members do.
    float: f64,
    int: i64,
    nil: void,
    node_path: NodePath,
    object: extern struct {
        id: native.ObjectID,
        object: *classes.core.Object,
    },
    packed_byte_array: *PackedArrayRef(PackedByteArray),
    packed_color_array: *PackedArrayRef(PackedColorArray),
    packed_float32_array: *PackedArrayRef(PackedFloat32Array),
    packed_float64_array: *PackedArrayRef(PackedFloat64Array),
    packed_int32_array: *PackedArrayRef(PackedInt32Array),
    packed_int64_array: *PackedArrayRef(PackedInt64Array),
    packed_string_array: *PackedArrayRef(PackedStringArray),
    packed_vector2_array: *PackedArrayRef(PackedVector2Array),
    packed_vector3_array: *PackedArrayRef(PackedVector3Array),
    packed_vector4_array: *PackedArrayRef(PackedVector4Array),
    plane: Plane,
    projection: *Projection,
    quaternion: Quaternion,
    rect2: Rect2,
    rect2i: Rect2i,
    rid: RID,
    signal: Signal,
    string: String,
    string_name: StringName,
    transform2d: *Transform2D,
    transform3d: *Transform3D,
    vector2: Vector2,
    vector2i: Vector2i,
    vector3: Vector3,
    vector3i: Vector3i,
    vector4: Vector4,
    vector4i: Vector4i,
    // max = 38,
};

const VariantWrapped = extern struct {
    tag: interface.VariantType align(@alignOf(Variant)),
    data: Data align(@alignOf(Variant)),

    fn toVariant(self: *const @This()) Variant {
        return @as(*const Variant, @ptrCast(self)).*;
    }
};

comptime {
    std.debug.assert(@sizeOf(VariantWrapped) == @sizeOf(Variant));
    std.debug.assert(@alignOf(VariantWrapped) == @alignOf(Variant));
    std.debug.assert(@offsetOf(VariantWrapped, "data") == 8);
}

// @section_end artifact Data
// @section artifact wrap
/// Creates a **borrowed** Variant view of `value` for a raw binding call.
///
/// `T` is the value type; `value` must be `*T`, `*const T`, `?*T` or
/// `?*const T`. A `null` optional pointer produces `Variant.nil`. No engine
/// allocation happens and no reference counts change. Pointer-backed payloads
/// alias the caller's storage; scalar and plain-value payloads are copied. The
/// result is only valid while that storage is alive and must never be destroyed
/// through the Variant API.
///
/// Scalars are written in their canonical Variant payload form: `bool` ->
/// `bool`, every integer/enum/packed bitfield -> canonical `i64` payload
/// (unsigned 64-bit backings bit-cast), `float` -> C++ `double` payload.
/// All inline builtins are handled here (`String`, `StringName`, `NodePath`,
/// `RID`, `Callable`, `Signal`, `Array`, `Dictionary`, the vector/rect types,
/// `Plane`, `Quaternion`, and `Color`); any generated opaque class pointer is
/// handled as an object. This raw-layer helper remains pointer-based and is a
/// subset of the public codegen `Variant.wrap`.
///
/// Packed arrays and heap-backed builtins (`AABB`, `Basis`, `Projection`,
/// `Transform2D`, `Transform3D`) compile-error: their Variant payload is an
/// engine-owned allocation or copy-on-write ref, so they need the owning
/// Variant constructors.
pub fn wrap(dispatcher: anytype, comptime T: type, value: anytype) Variant {
    const VT = @TypeOf(value);
    if (VT != *const T and
        VT != *T and
        VT != ?*T and
        VT != ?*const T)
        @compileError(std.fmt.comptimePrint(
            "Variant.wrap expects a pointer to {s} (or an optional pointer), found: {s}",
            .{ @typeName(T), @typeName(VT) },
        ));

    if (comptime traits.isPackedArray(T)) {
        @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
            ": packed arrays are copy-on-write engine values. Use the owning Variant constructor instead.");
    }
    if (comptime traits.isHeapBuiltin(T)) {
        @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
            ": the engine keeps it behind an owned heap allocation. Use the owning Variant constructor instead.");
    }

    const v = if (VT == ?*T or VT == ?*const T) blk: {
        const ov = value orelse {
            return Variant.nil;
        };
        break :blk ov;
    } else value;

    switch (T) {
        String => return borrowed(.string, .{ .string = v.* }),
        StringName => return borrowed(.string_name, .{ .string_name = v.* }),
        classes.core.Object => {
            const object: *classes.core.Object = @constCast(@as(*const classes.core.Object, @ptrCast(v)));
            const instance_id = classes.core.Object.getInstanceId(object, dispatcher);
            return borrowed(.object, .{
                .object = .{
                    .id = .{ .id = instance_id },
                    .object = object,
                },
            });
        },
        NodePath => return borrowed(.node_path, .{ .node_path = v.* }),
        RID => return borrowed(.rid, .{ .rid = v.* }),
        Callable => return borrowed(.callable, .{ .callable = v.* }),
        Signal => return borrowed(.signal, .{ .signal = v.* }),
        Array => return borrowed(.array, .{ .array = v.* }),
        Dictionary => return borrowed(.dictionary, .{ .dictionary = v.* }),
        Vector2 => return borrowed(.vector2, .{ .vector2 = v.* }),
        Vector2i => return borrowed(.vector2i, .{ .vector2i = v.* }),
        Vector3 => return borrowed(.vector3, .{ .vector3 = v.* }),
        Vector3i => return borrowed(.vector3i, .{ .vector3i = v.* }),
        Vector4 => return borrowed(.vector4, .{ .vector4 = v.* }),
        Vector4i => return borrowed(.vector4i, .{ .vector4i = v.* }),
        Rect2 => return borrowed(.rect2, .{ .rect2 = v.* }),
        Rect2i => return borrowed(.rect2i, .{ .rect2i = v.* }),
        Plane => return borrowed(.plane, .{ .plane = v.* }),
        Quaternion => return borrowed(.quaternion, .{ .quaternion = v.* }),
        Color => return borrowed(.color, .{ .color = v.* }),
        else => if (comptime @typeInfo(T) == .@"opaque" and @hasDecl(T, "GodotClassName")) {
            // Any generated engine class pointer is a Variant object. This is
            // intentionally broader than the exact Object case above so future
            // vararg fixed arguments such as *Node keep working.
            const object: *classes.core.Object = @constCast(@as(*const classes.core.Object, @ptrCast(v)));
            const instance_id = classes.core.Object.getInstanceId(object, dispatcher);
            return borrowed(.object, .{
                .object = .{
                    .id = .{ .id = instance_id },
                    .object = object,
                },
            });
        } else switch (@typeInfo(T)) {
            .bool => return borrowed(.bool, .{ .bool = v.* }),
            .int => return borrowed(.int, .{ .int = canonicalInt(T, v.*) }),
            .float => return borrowed(.float, .{ .float = @as(f64, @floatCast(v.*)) }),
            .@"enum" => |info| return borrowed(.int, .{
                .int = canonicalInt(info.tag_type, @backingInt(v.*)),
            }),
            .@"struct" => |info| {
                const Backing = info.backing_integer orelse
                    @compileError("Variant.wrap does not support type: " ++ @typeName(T));
                const bits: Backing = @bitCast(v.*);
                return borrowed(.int, .{ .int = canonicalInt(Backing, bits) });
            },
            else => @compileError("Variant.wrap does not support type: " ++ @typeName(T)),
        },
    }
}

/// Assembles a borrowed Variant from a tag and its inline data payload.
fn borrowed(comptime tag: interface.VariantType, data: Data) Variant {
    const result: VariantWrapped = .{ .tag = tag, .data = data };
    return result.toVariant();
}

/// Writes a scalar into the canonical Variant payload: integers, enums and
/// packed bitfields share the `i64` payload, unsigned 64-bit values bit-cast
/// because the payload bits are identical.
fn canonicalInt(comptime T: type, value: T) i64 {
    const info = @typeInfo(T);
    if (info != .int) @compileError("canonicalInt expects an integer type, found: " ++ @typeName(T));
    if (info.int.bits == 64 and info.int.signedness == .unsigned) return @bitCast(value);
    return @intCast(value);
}

// @section_end artifact wrap
// @section artifact nil
/// Precomputed nil Variant value. It owns no engine-managed references; copy it
/// when a separate value is needed.
pub const nil: Variant = blk: {
    const wrapped: VariantWrapped = .{
        .tag = .nil,
        .data = .{ .nil = {} },
    };
    break :blk wrapped.toVariant();
};

// @section_end artifact nil
// @section artifact asInt
pub fn asInt(self: Variant) i64 {
    const wrapped: VariantWrapped = @as(*const VariantWrapped, @ptrCast(&self)).*;
    return wrapped.data.int;
}

// @section_end artifact asInt
// @section artifact asCallable
pub fn asCallable(self: Variant) Callable {
    const wrapped: VariantWrapped = @as(*const VariantWrapped, @ptrCast(&self)).*;
    return wrapped.data.callable;
}

// @section_end artifact asCallable

// @section file
const classes = @import("../classes/classes.zig");
const native = @import("../native.zig");
const traits = @import("traits.zig");
// @section_end file
