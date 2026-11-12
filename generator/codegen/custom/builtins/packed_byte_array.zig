// @method index

pub inline fn index(self: *PackedByteArray, p_index: i64) *u8 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_byte_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedByteArray, p_index: i64) *const u8 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_byte_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
