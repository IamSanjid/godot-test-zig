// @section artifact index

pub inline fn index(self: *Dictionary, p_key: *const builtins.Variant) *builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.dictionary_operator_index, .{ self, p_key })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const Dictionary, p_key: *const builtins.Variant) *const builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.dictionary_operator_index_const, .{ self, p_key })));
}
// @section_end artifact indexConst

// @section artifact setTyped

/// Makes this dictionary typed to store keys of `K` and values of `V`. A
/// `Variant` side stays untyped, and two untyped sides are a no-op; every other
/// side needs a `Variant` representation, and object sides pass their engine
/// class name. The engine rejects a script without a base class name. See
/// `setTypedAs` for the engine-side contract.
pub inline fn setTyped(
    self: *Dictionary,
    comptime K: type,
    comptime V: type,
    key_script: ?*const builtins.Variant,
    value_script: ?*const builtins.Variant,
) void {
    const key_type: bindings.interface.VariantType = comptime if (K == builtins.Variant) .nil else builtins.Variant.typeFor(K) orelse
        @compileError("Dictionary.setTyped: '" ++ @typeName(K) ++ "' has no Variant representation");
    const value_type: bindings.interface.VariantType = comptime if (V == builtins.Variant) .nil else builtins.Variant.typeFor(V) orelse
        @compileError("Dictionary.setTyped: '" ++ @typeName(V) ++ "' has no Variant representation");
    if (key_type == .nil and value_type == .nil) return;
    const key_class_name = builtins.StringName.fromComptimeLatin1(reflect.classNameOf(K));
    const value_class_name = builtins.StringName.fromComptimeLatin1(reflect.classNameOf(V));
    self.setTypedAs(
        key_type,
        if (key_type == .object) &key_class_name else null,
        if (key_type == .object) key_script else null,
        value_type,
        if (value_type == .object) &value_class_name else null,
        if (value_type == .object) value_script else null,
    );
}
// @section_end artifact setTyped

// @section artifact setTypedAs

/// Makes this dictionary typed from engine metadata for both sides.
///
/// Each side is a key or value Variant type with an object `class_name` where
/// applicable and a `script`; both may be null. The C interface dereferences all
/// four pointers unconditionally (nulls become an empty name and a nil script).
/// The engine only accepts this on an empty, uniquely referenced dictionary, and
/// the types cannot be changed afterwards.
pub inline fn setTypedAs(
    self: *Dictionary,
    key_type: bindings.interface.VariantType,
    key_class_name: ?*const builtins.StringName,
    key_script: ?*const builtins.Variant,
    value_type: bindings.interface.VariantType,
    value_class_name: ?*const builtins.StringName,
    value_script: ?*const builtins.Variant,
) void {
    const empty_name = builtins.StringName.fromComptimeLatin1("");
    var no_script = builtins.Variant.nil;
    runtime.dispatch(.dictionary_set_typed, .{
        self,
        key_type,
        key_class_name orelse &empty_name,
        key_script orelse &no_script,
        value_type,
        value_class_name orelse &empty_name,
        value_script orelse &no_script,
    });
}
// @section_end artifact setTypedAs

// @section file

const reflect = @import("../../reflect/reflect.zig");
// @section_end file
