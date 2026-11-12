// @method index

pub inline fn index(self: *PackedStringArray, p_index: i64) *builtins.String {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_string_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedStringArray, p_index: i64) *const builtins.String {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_string_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
