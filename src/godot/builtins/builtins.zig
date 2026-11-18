pub const AABB = @import("aabb.zig").AABB;
pub const Array = @import("generated/array.zig").Array;
pub const Basis = @import("basis.zig").Basis;
pub const Callable = @import("generated/callable.zig").Callable;
pub const Color = @import("color.zig").Color;
pub const Dictionary = @import("generated/dictionary.zig").Dictionary;
pub const NodePath = @import("generated/node_path.zig").NodePath;
pub const PackedByteArray = @import("generated/packed_byte_array.zig").PackedByteArray;
pub const PackedColorArray = @import("generated/packed_color_array.zig").PackedColorArray;
pub const PackedFloat32Array = @import("generated/packed_float32_array.zig").PackedFloat32Array;
pub const PackedFloat64Array = @import("generated/packed_float64_array.zig").PackedFloat64Array;
pub const PackedInt32Array = @import("generated/packed_int32_array.zig").PackedInt32Array;
pub const PackedInt64Array = @import("generated/packed_int64_array.zig").PackedInt64Array;
pub const PackedStringArray = @import("generated/packed_string_array.zig").PackedStringArray;
pub const PackedVector2Array = @import("generated/packed_vector2_array.zig").PackedVector2Array;
pub const PackedVector3Array = @import("generated/packed_vector3_array.zig").PackedVector3Array;
pub const PackedVector4Array = @import("generated/packed_vector4_array.zig").PackedVector4Array;
pub const Plane = @import("plane.zig").Plane;
pub const Projection = @import("projection.zig").Projection;
pub const Quaternion = @import("quaternion.zig").Quaternion;
pub const rect = @import("rect.zig");
pub const Rect2 = rect.Rect2;
pub const Rect2i = rect.Rect2i;
pub const RID = @import("rid.zig").RID;
pub const Signal = @import("generated/signal.zig").Signal;
pub const String = @import("generated/string.zig").String;
pub const StringName = @import("generated/string_name.zig").StringName;
pub const Transform2D = @import("transform2d.zig").Transform2D;
pub const Transform3D = @import("transform3d.zig").Transform3D;
pub const vector = @import("vector.zig");
pub const Vector2 = vector.Vector2;
pub const Vector2i = vector.Vector2i;
pub const Vector3 = vector.Vector3;
pub const Vector3i = vector.Vector3i;
pub const Vector4 = vector.Vector4;
pub const Vector4i = vector.Vector4i;
pub const Variant = @import("variant.zig").Variant;

const bindings = @import("bindings");

// Hand-written builtin structs must stay layout-compatible with the generated
// binding structs: `toBinding`/`fromBinding` are pointer bit-casts. Generated
// builtins already emit their own layout checks; this covers the hand-written
// ones (and therefore both precision configurations).
comptime {
    layoutCheck(AABB, bindings.builtins.aabb.AABB);
    layoutCheck(Basis, bindings.builtins.basis.Basis);
    layoutCheck(Color, bindings.builtins.color.Color);
    layoutCheck(Plane, bindings.builtins.plane.Plane);
    layoutCheck(Projection, bindings.builtins.projection.Projection);
    layoutCheck(Quaternion, bindings.builtins.quaternion.Quaternion);
    layoutCheck(Rect2, bindings.builtins.rect2.Rect2);
    layoutCheck(Rect2i, bindings.builtins.rect2i.Rect2i);
    layoutCheck(RID, bindings.builtins.rid.RID);
    layoutCheck(Transform2D, bindings.builtins.transform2d.Transform2D);
    layoutCheck(Transform3D, bindings.builtins.transform3d.Transform3D);
    layoutCheck(Vector2, bindings.builtins.vector2.Vector2);
    layoutCheck(Vector2i, bindings.builtins.vector2i.Vector2i);
    layoutCheck(Vector3, bindings.builtins.vector3.Vector3);
    layoutCheck(Vector3i, bindings.builtins.vector3i.Vector3i);
    layoutCheck(Vector4, bindings.builtins.vector4.Vector4);
    layoutCheck(Vector4i, bindings.builtins.vector4i.Vector4i);
}

fn layoutCheck(comptime Codegen: type, comptime Binding: type) void {
    if (@sizeOf(Codegen) != @sizeOf(Binding)) {
        @compileError("hand-written builtin layout mismatch: " ++ @typeName(Codegen));
    }
    if (@alignOf(Codegen) != @alignOf(Binding)) {
        @compileError("hand-written builtin alignment mismatch: " ++ @typeName(Codegen));
    }
}
