// @section artifact index

pub inline fn index(self: *PackedInt64Array, p_index: i64) *i64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int64_array_operator_index, .{ self, p_index })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const PackedInt64Array, p_index: i64) *const i64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_int64_array_operator_index_const, .{ self, p_index })));
}
// @section_end artifact indexConst

// @section artifact bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedInt64Array) []i64 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]i64, @ptrCast(start))[0..len];
}
// @section_end artifact bytes

// @section artifact bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedInt64Array) []const i64 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const i64, @ptrCast(start))[0..len];
}
// @section_end artifact bytesConst
