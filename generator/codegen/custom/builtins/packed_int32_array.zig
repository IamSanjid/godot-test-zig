// @method index

pub inline fn index(self: *PackedInt32Array, p_index: i64) *i32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int32_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedInt32Array, p_index: i64) *const i32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int32_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
