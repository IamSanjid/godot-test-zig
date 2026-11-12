// @method index

pub inline fn index(self: *PackedVector2Array, p_index: i64) *builtins.Vector2 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector2_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedVector2Array, p_index: i64) *const builtins.Vector2 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector2_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
