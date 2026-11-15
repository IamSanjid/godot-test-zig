// @method index

pub inline fn index(self: *PackedFloat32Array, p_index: i64) *f32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float32_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedFloat32Array, p_index: i64) *const f32 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float32_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst

// @method bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedFloat32Array) []f32 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]f32, @ptrCast(start))[0..len];
}
// @method_end bytes

// @method bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedFloat32Array) []const f32 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const f32, @ptrCast(start))[0..len];
}
// @method_end bytesConst
