// @method index

pub inline fn index(self: *PackedVector4Array, p_index: i64) *builtins.Vector4 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector4_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedVector4Array, p_index: i64) *const builtins.Vector4 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector4_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
