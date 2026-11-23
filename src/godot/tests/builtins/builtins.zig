//! Compile-only layout coverage: hand-written builtins must stay layout-compatible
//! with the generated binding structs.

// Hand-written builtin structs must stay layout-compatible with the generated
// binding structs: `toBinding`/`fromBinding` are pointer bit-casts. Generated
// builtins already emit their own layout checks; this covers the hand-written
// ones (and therefore both precision configurations).
comptime {
    layoutCheck(godot.builtins.AABB, bindings.builtins.aabb.AABB);
    layoutCheck(godot.builtins.Basis, bindings.builtins.basis.Basis);
    layoutCheck(godot.builtins.Color, bindings.builtins.color.Color);
    layoutCheck(godot.builtins.Plane, bindings.builtins.plane.Plane);
    layoutCheck(godot.builtins.Projection, bindings.builtins.projection.Projection);
    layoutCheck(godot.builtins.Quaternion, bindings.builtins.quaternion.Quaternion);
    layoutCheck(godot.builtins.Rect2, bindings.builtins.rect2.Rect2);
    layoutCheck(godot.builtins.Rect2i, bindings.builtins.rect2i.Rect2i);
    layoutCheck(godot.builtins.RID, bindings.builtins.rid.RID);
    layoutCheck(godot.builtins.Transform2D, bindings.builtins.transform2d.Transform2D);
    layoutCheck(godot.builtins.Transform3D, bindings.builtins.transform3d.Transform3D);
    layoutCheck(godot.builtins.Vector2, bindings.builtins.vector2.Vector2);
    layoutCheck(godot.builtins.Vector2i, bindings.builtins.vector2i.Vector2i);
    layoutCheck(godot.builtins.Vector3, bindings.builtins.vector3.Vector3);
    layoutCheck(godot.builtins.Vector3i, bindings.builtins.vector3i.Vector3i);
    layoutCheck(godot.builtins.Vector4, bindings.builtins.vector4.Vector4);
    layoutCheck(godot.builtins.Vector4i, bindings.builtins.vector4i.Vector4i);
}

fn layoutCheck(comptime Codegen: type, comptime Binding: type) void {
    if (@sizeOf(Codegen) != @sizeOf(Binding)) {
        @compileError("hand-written builtin layout mismatch: " ++ @typeName(Codegen));
    }
    if (@alignOf(Codegen) != @alignOf(Binding)) {
        @compileError("hand-written builtin alignment mismatch: " ++ @typeName(Codegen));
    }
}

const godot = @import("godot");
const bindings = godot.bindings;
