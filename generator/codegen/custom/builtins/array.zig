// @section artifact index

pub inline fn index(self: *Array, p_index: usize) *builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.array_operator_index, .{ self, @intCast(p_index) })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const Array, p_index: usize) *const builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.array_operator_index_const, .{ self, @intCast(p_index) })));
}
// @section_end artifact indexConst

// @section artifact setTyped

/// Makes this array typed to store `T` elements. `Variant` leaves the array
/// untyped; every other element type must have a `Variant` representation, and
/// object elements pass their engine class name. See `setTypedAs` for `script`.
pub inline fn setTyped(self: *Array, comptime T: type, script: ?*const builtins.Variant) void {
    const variant_type: bindings.interface.VariantType = comptime if (T == builtins.Variant) .nil else builtins.Variant.typeFor(T) orelse
        @compileError("Array.setTyped: '" ++ @typeName(T) ++ "' has no Variant representation");
    if (variant_type == .nil) return;
    if (variant_type == .object) {
        const class_name = builtins.StringName.fromComptimeLatin1(reflect.classNameOf(T));
        self.setTypedAs(variant_type, &class_name, script);
    } else {
        self.setTypedAs(variant_type, null, null);
    }
}
// @section_end artifact setTyped

// @section artifact setTypedAs

/// Makes this array typed from engine metadata.
///
/// `variant_type` is the element Variant type; `class_name` and `script` describe
/// an object element and may be null. The C interface dereferences both pointers
/// unconditionally (nulls become an empty name and a nil script). The engine only
/// accepts this on an empty, uniquely referenced array, and the element type
/// cannot be changed afterwards.
pub inline fn setTypedAs(
    self: *Array,
    variant_type: bindings.interface.VariantType,
    class_name: ?*const builtins.StringName,
    script: ?*const builtins.Variant,
) void {
    const empty_name = builtins.StringName.fromComptimeLatin1("");
    var no_script = builtins.Variant.nil;
    runtime.dispatch(.array_set_typed, .{ self, variant_type, class_name orelse &empty_name, script orelse &no_script });
}
// @section_end artifact setTypedAs

// @section file

const reflect = @import("../../reflect/reflect.zig");
// @section_end file
