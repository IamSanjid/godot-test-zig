// @method index

pub inline fn index(self: *Array, p_index: usize) *builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.array_operator_index, .{ self, @intCast(p_index) })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const Array, p_index: usize) *const builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.array_operator_index_const, .{ self, @intCast(p_index) })));
}
// @method_end indexConst
