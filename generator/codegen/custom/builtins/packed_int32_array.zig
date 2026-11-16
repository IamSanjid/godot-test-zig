// @section artifact index

pub inline fn index(self: *PackedInt32Array, p_index: i64) *i32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int32_array_operator_index, .{ self, p_index })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const PackedInt32Array, p_index: i64) *const i32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int32_array_operator_index_const, .{ self, p_index })));
}
// @section_end artifact indexConst

// @section artifact bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedInt32Array) []i32 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]i32, @ptrCast(start))[0..len];
}
// @section_end artifact bytes

// @section artifact bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedInt32Array) []const i32 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const i32, @ptrCast(start))[0..len];
}
// @section_end artifact bytesConst
