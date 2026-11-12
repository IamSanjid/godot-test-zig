// @method index

pub inline fn index(self: *PackedColorArray, p_index: i64) *builtins.Color {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_color_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedColorArray, p_index: i64) *const builtins.Color {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_color_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst
