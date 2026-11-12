// @method index

pub inline fn index(self: *Dictionary, p_key: *const builtins.Variant) *builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.dictionary_operator_index, .{ self, p_key })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const Dictionary, p_key: *const builtins.Variant) *const builtins.Variant {
    return @ptrCast(@alignCast(runtime.dispatch(.dictionary_operator_index_const, .{ self, p_key })));
}
// @method_end indexConst
