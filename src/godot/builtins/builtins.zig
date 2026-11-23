pub const aabb = @import("aabb.zig");
pub const AABB = aabb.AABB;

pub const Array = @import("generated/array.zig").Array;

pub const basis = @import("basis.zig");
pub const Basis = basis.Basis;

pub const Callable = @import("generated/callable.zig").Callable;

pub const Color = @import("color.zig").Color;

pub const constants = @import("constants.zig");

pub const Dictionary = @import("generated/dictionary.zig").Dictionary;

pub const NodePath = @import("generated/node_path.zig").NodePath;

pub const ok_color = @import("ok_color.zig");

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

pub const plane = @import("plane.zig");
pub const Plane = plane.Plane;

pub const projection = @import("projection.zig");
pub const Projection = projection.Projection;

pub const quaternion = @import("quaternion.zig");
pub const Quaternion = quaternion.Quaternion;

pub const rect = @import("rect.zig");
pub const Rect2 = rect.Rect2;
pub const Rect2i = rect.Rect2i;

pub const RID = @import("rid.zig").RID;

pub const Signal = @import("generated/signal.zig").Signal;

pub const String = @import("generated/string.zig").String;

pub const StringName = @import("generated/string_name.zig").StringName;

pub const transform2d = @import("transform2d.zig");
pub const Transform2D = transform2d.Transform2D;

pub const transform3d = @import("transform3d.zig");
pub const Transform3D = transform3d.Transform3D;

pub const Variant = @import("variant.zig").Variant;

pub const vector = @import("vector.zig");
pub const Vector2 = vector.Vector2;
pub const Vector2i = vector.Vector2i;
pub const Vector3 = vector.Vector3;
pub const Vector3i = vector.Vector3i;
pub const Vector4 = vector.Vector4;
pub const Vector4i = vector.Vector4i;

/// True for builtins with engine-owned storage and a `deinit` contract.
pub fn isManaged(comptime T: type) bool {
    return bindings.builtins.traits.isManagedBuiltin(T);
}

const bindings = @import("bindings");
