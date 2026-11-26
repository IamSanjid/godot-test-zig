// @section artifact index

pub inline fn index(self: *PackedVector4Array, p_index: i64) *builtins.Vector4 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector4_array_operator_index, .{ self, p_index })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const PackedVector4Array, p_index: i64) *const builtins.Vector4 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector4_array_operator_index_const, .{ self, p_index })));
}
// @section_end artifact indexConst

// @section artifact asSlice

/// Mutable view (forces a COW detach).
pub inline fn asSlice(self: *PackedVector4Array) []builtins.Vector4 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]builtins.Vector4, @ptrCast(start))[0..len];
}
// @section_end artifact asSlice

// @section artifact asSliceConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn asSliceConst(self: *const PackedVector4Array) []const builtins.Vector4 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const builtins.Vector4, @ptrCast(start))[0..len];
}
// @section_end artifact asSliceConst
