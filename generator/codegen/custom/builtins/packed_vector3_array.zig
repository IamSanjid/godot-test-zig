// @method index

pub inline fn index(self: *PackedVector3Array, p_index: i64) *builtins.Vector3 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector3_array_operator_index, .{ self, p_index })));
}
// @method_end index

// @method indexConst

pub inline fn indexConst(self: *const PackedVector3Array, p_index: i64) *const builtins.Vector3 {
    return @ptrCast(@alignCast(runtime.dispatch(.packed_vector3_array_operator_index_const, .{ self, p_index })));
}
// @method_end indexConst

// @method bytes

/// Mutable view (forces a COW detach).
pub inline fn bytes(self: *PackedVector3Array) []builtins.Vector3 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.index(0);
    return @as([*]builtins.Vector3, @ptrCast(start))[0..len];
}
// @method_end bytes

// @method bytesConst

/// Read-only view. Invalid after the array is modified or freed.
pub inline fn bytesConst(self: *const PackedVector3Array) []const builtins.Vector3 {
    const len: usize = @intCast(self.size());
    if (len == 0) return &.{};
    const start = self.indexConst(0);
    return @as([*]const builtins.Vector3, @ptrCast(start))[0..len];
}
// @method_end bytesConst
