// @struct Variant
const Data = extern union {
    aabb: *AABB,
    array: *Array,
    basis: *Basis,
    bool: bool,
    callable: Callable,
    color: Color,
    dictionary: *Dictionary,
    float: if (@sizeOf(Variant) == 40) f64 else f32,
    int: i64,
    nil: void,
    node_path: NodePath,
    object: extern struct {
        id: native.ObjectID,
        object: *classes.core.Object,
    },
    packed_byte_array: ?*anyopaque,
    packed_color_array: ?*anyopaque,
    packed_float32_array: ?*anyopaque,
    packed_float64_array: ?*anyopaque,
    packed_int32_array: ?*anyopaque,
    packed_int64_array: ?*anyopaque,
    packed_string_array: ?*anyopaque,
    packed_vector2_array: ?*anyopaque,
    packed_vector3_array: ?*anyopaque,
    packed_vector4_array: ?*anyopaque,
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
}

pub fn fromPtr(dispatcher: anytype, comptime T: type, value: anytype) Variant {
    const VT = @TypeOf(value);
    if (VT != *const T and
        VT != *T and
        VT != ?*T and
        VT != ?*const T)
        @compileError(std.fmt.comptimePrint(
            "Please provide value as a pointer to {s} or const {s} or ?{s} or ?const {s}, found: {s}",
            .{
                @typeName(T), @typeName(T), @typeName(T), @typeName(T), @typeName(VT),
            },
        ));
    const v = if (VT == ?*T or VT == ?*const T) blk: {
        const ov = value orelse {
            return nil();
        };
        break :blk ov;
    } else value;
    switch (T) {
        String => {
            const wrapped: VariantWrapped = .{
                .tag = .string,
                .data = .{ .string = v.* },
            };
            return wrapped.toVariant();
        },
        StringName => {
            const wrapped: VariantWrapped = .{
                .tag = .string_name,
                .data = .{ .string_name = v.* },
            };
            return wrapped.toVariant();
        },
        Callable => {
            const wrapped: VariantWrapped = .{
                .tag = .callable,
                .data = .{ .callable = v.* },
            };
            return wrapped.toVariant();
        },
        Signal => {
            const wrapped: VariantWrapped = .{
                .tag = .signal,
                .data = .{ .signal = v.* },
            };
            return wrapped.toVariant();
        },
        classes.core.Object => {
            const wrapped: VariantWrapped = .{
                .tag = .object,
                .data = .{
                    .object = .{
                        .id = @bitCast(classes.core.Object.getInstanceId(dispatcher, v)),
                        .object = v,
                    },
                },
            };
            return wrapped.toVariant();
        },
        else => {
            const info = @typeInfo(T);
            switch (info) {
                .int => {
                    const wrapped: VariantWrapped = .{
                        .tag = .int,
                        .data = .{ .int = @intCast(v.*) },
                    };
                    return wrapped.toVariant();
                },
                .float => {
                    const wrapped: VariantWrapped = .{
                        .tag = .float,
                        .data = .{ .float = @floatCast(v.*) },
                    };
                    return wrapped.toVariant();
                },
                else => @compileError("Variant.fromPtr not supported for type: " ++ @typeName(T)),
            }
        },
    }
}

pub fn nil() Variant {
    const wrapped: VariantWrapped = .{
        .tag = .nil,
        .data = .{ .nil = {} },
    };
    return @bitCast(wrapped);
}

pub fn asInt(self: Variant) i64 {
    const wrapped: VariantWrapped = @bitCast(self);
    return wrapped.data.int;
}

pub fn asCallable(self: Variant) Callable {
    const wrapped: VariantWrapped = @bitCast(self);
    return wrapped.data.callable;
}
// @struct_end Variant

// @namespace
const classes = @import("../classes/classes.zig");
const native = @import("../native.zig");
// @namespace_end
