// @method index

pub inline fn index(self: *PackedFloat64Array, p_index: i64) *f64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float64_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedFloat64Array, p_index: i64) *const f64 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_float64_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst

// @method bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedFloat64Array) []f64 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]f64, @ptrCast(start))[0..len];
}
// @method_end bytes

// @method bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedFloat64Array) []const f64 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const f64, @ptrCast(start))[0..len];
}
// @method_end bytesConst
