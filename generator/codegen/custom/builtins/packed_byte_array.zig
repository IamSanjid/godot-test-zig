// @section artifact index

pub inline fn index(self: *PackedByteArray, p_index: i64) *u8 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_byte_array_operator_index, .{ self, p_index })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const PackedByteArray, p_index: i64) *const u8 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_byte_array_operator_index_const, .{ self, p_index })));
}
// @section_end artifact indexConst

// @section artifact asSlice

/// Mutable view (forces a COW detach).
pub inline fn asSlice(self: *PackedByteArray) []u8 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]u8, @ptrCast(start))[0..len];
}
// @section_end artifact asSlice

// @section artifact asSliceConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn asSliceConst(self: *const PackedByteArray) []const u8 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const u8, @ptrCast(start))[0..len];
}
// @section_end artifact asSliceConst
