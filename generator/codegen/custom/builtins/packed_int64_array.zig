// @method index

pub inline fn index(self: *PackedInt64Array, p_index: i64) *i64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int64_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedInt64Array, p_index: i64) *const i64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int64_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
