// @section artifact index

pub inline fn index(self: *PackedStringArray, p_index: i64) *builtins.String {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_string_array_operator_index, .{ self, p_index })));
}
// @section_end artifact index

// @section artifact indexConst

pub inline fn indexConst(self: *const PackedStringArray, p_index: i64) *const builtins.String {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_string_array_operator_index_const, .{ self, p_index })));
}
// @section_end artifact indexConst

// @section artifact bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedStringArray) []builtins.String {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]builtins.String, @ptrCast(start))[0..len];
}
// @section_end artifact bytes

// @section artifact bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedStringArray) []const builtins.String {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const builtins.String, @ptrCast(start))[0..len];
}
// @section_end artifact bytesConst
