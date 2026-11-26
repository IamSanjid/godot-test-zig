//! Hand-written runtime tests. zig build test-godot compiles and runs this
//! test root after regenerating bindings/codegen.

test "hand-written runtime tests are linked" {
    _ = @import("abi.zig");
    _ = @import("annotations/annotations.zig");
    _ = @import("annotations/base.zig");
    _ = @import("annotations/callbacks.zig");
    _ = @import("annotations/constants.zig");
    _ = @import("annotations/conversion.zig");
    _ = @import("annotations/on_ready.zig");
    _ = @import("annotations/override.zig");
    _ = @import("annotations/property.zig");
    _ = @import("annotations/property_hint.zig");
    _ = @import("annotations/signal.zig");
    _ = @import("builtins/aabb.zig");
    _ = @import("builtins/basis.zig");
    _ = @import("builtins/builtins.zig");
    _ = @import("builtins/color.zig");
    _ = @import("builtins/constants.zig");
    _ = @import("builtins/ok_color.zig");
    _ = @import("builtins/plane.zig");
    _ = @import("builtins/projection.zig");
    _ = @import("builtins/quaternion.zig");
    _ = @import("builtins/rect.zig");
    _ = @import("builtins/rid.zig");
    _ = @import("builtins/transform2d.zig");
    _ = @import("builtins/transform3d.zig");
    _ = @import("builtins/variant.zig");
    _ = @import("builtins/vector.zig");
    _ = @import("classes.zig");
    _ = @import("collections.zig");
    _ = @import("conversion.zig");
    _ = @import("ownership.zig");
    _ = @import("ptrcall.zig");
    _ = @import("reflect/base.zig");
    _ = @import("reflect/extension.zig");
    _ = @import("reflect/hierarchy.zig");
    _ = @import("reflect/meta.zig");
    _ = @import("reflect/objects.zig");
    _ = @import("reflect/reflect.zig");
    _ = @import("registration/classdb.zig");
    _ = @import("registration/instance.zig");
    _ = @import("registration/property.zig");
    _ = @import("registration/registry.zig");
}
