// @method index

pub inline fn index(self: *PackedVector3Array, p_index: i64) *builtins.Vector3 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector3_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedVector3Array, p_index: i64) *const builtins.Vector3 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector3_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
