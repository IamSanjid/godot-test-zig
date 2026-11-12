// @method index

pub inline fn index(self: *PackedFloat64Array, p_index: i64) *f64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float64_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedFloat64Array, p_index: i64) *const f64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float64_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
