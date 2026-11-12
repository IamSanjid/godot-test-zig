// @method index

pub inline fn index(self: *PackedFloat32Array, p_index: i64) *f32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float32_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedFloat32Array, p_index: i64) *const f32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float32_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
