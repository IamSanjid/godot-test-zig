pub const Variant = extern struct {
    tag: interface.VariantType align(@alignOf(bindings.builtins.Variant)),
    data: Data align(@alignOf(bindings.builtins.Variant)),

    const Data = extern union {
        aabb: *AABB,
        array: *Array,
        basis: *Basis,
        bool: bool,
        callable: Callable,
        color: Color,
        dictionary: *Dictionary,
        float: if (bindings.is_double_precision) f64 else f32,
        int: i64,
        nil: void,
        node_path: NodePath,
        object: extern struct {
            id: native.ObjectID,
            object: *Object,
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

    pub fn toBinding(self: *const Variant) bindings.builtins.Variant {
        return @as(*const bindings.builtins.Variant, @ptrCast(self)).*;
    }

    pub fn fromBinding(v: anytype) Variant {
        const T = @TypeOf(v);
        return switch (T) {
            *bindings.builtins.Variant => @as(*Variant, @ptrCast(v)).*,
            *const bindings.builtins.Variant => @as(*const Variant, @ptrCast(v)).*,
            bindings.builtins.Variant => @as(*const Variant, @ptrCast(&v)).*,
            else => @compileError("Expected bindings.builtins.Variant by value or a pointer to it, found: " ++ @typeName(T)),
        };
    }

    pub fn fromPtr(comptime T: type, value: anytype) Variant {
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
                const wrapped: Variant = .{
                    .tag = .string,
                    .data = .{ .string = v.* },
                };
                return wrapped;
            },
            StringName => {
                const wrapped: Variant = .{
                    .tag = .string_name,
                    .data = .{ .string_name = v.* },
                };
                return wrapped;
            },
            Callable => {
                const wrapped: Variant = .{
                    .tag = .callable,
                    .data = .{ .callable = v.* },
                };
                return wrapped;
            },
            Signal => {
                const wrapped: Variant = .{
                    .tag = .signal,
                    .data = .{ .signal = v.* },
                };
                return wrapped;
            },
            Vector2 => {
                const wrapped: Variant = .{
                    .tag = .vector2,
                    .data = .{ .vector2 = v.* },
                };
                return wrapped;
            },
            Object => {
                const wrapped: Variant = .{
                    .tag = .object,
                    .data = .{
                        .object = .{
                            .id = @bitCast(classes.core.Object.getInstanceId(v)),
                            .object = v,
                        },
                    },
                };
                return wrapped;
            },
            else => {
                const info = @typeInfo(T);
                switch (info) {
                    .int => {
                        const wrapped: Variant = .{
                            .tag = .int,
                            .data = .{ .int = @intCast(v.*) },
                        };
                        return wrapped;
                    },
                    .float => {
                        const wrapped: Variant = .{
                            .tag = .float,
                            .data = .{ .float = @floatCast(v.*) },
                        };
                        return wrapped;
                    },
                    else => @compileError("Variant.fromPtr not supported for type: " ++ @typeName(T)),
                }
            },
        }
    }

    pub fn nil() Variant {
        const wrapped: Variant = .{
            .tag = .nil,
            .data = .{ .nil = {} },
        };
        return wrapped;
    }

    pub fn asInt(self: *const Variant) i64 {
        assert(self.tag == .int);
        return self.data.int;
    }

    pub fn asCallable(self: *const Variant) Callable {
        assert(self.tag == .callable);
        return self.data.callable;
    }

    pub fn asObject(self: *const Variant) *Object {
        assert(self.tag == .object);
        return self.data.object.object;
    }
};

comptime {
    bindings.builtins.variant.checkTypeLayout(Variant);
}

const std = @import("std");
const assert = std.debug.assert;

const AABB = @import("aabb.zig").AABB;
const Array = builtins.Array;
const Basis = @import("basis.zig").Basis;
const Callable = builtins.Callable;
const Color = @import("color.zig").Color;
const Dictionary = builtins.Dictionary;
const NodePath = builtins.NodePath;
const Plane = @import("plane.zig").Plane;
const Projection = @import("projection.zig").Projection;
const Quaternion = @import("quaternion.zig").Quaternion;
const rect = @import("rect.zig");
const Rect2 = rect.Rect2;
const Rect2i = rect.Rect2i;
const RID = @import("rid.zig").RID;
const Signal = builtins.Signal;
const String = builtins.String;
const StringName = builtins.StringName;
const Transform2D = @import("transform2d.zig").Transform2D;
const Transform3D = @import("transform3d.zig").Transform3D;
const vector = @import("vector.zig");
const Vector2 = vector.Vector2;
const Vector2i = vector.Vector2i;
const Vector3 = vector.Vector3;
const Vector3i = vector.Vector3i;
const Vector4 = vector.Vector4;
const Vector4i = vector.Vector4i;

const bindings = @import("bindings");
const Object = classes.core.Object;
const interface = bindings.interface;
const native = bindings.native;

const builtins = @import("builtins.zig");
const classes = @import("../classes/classes.zig");
