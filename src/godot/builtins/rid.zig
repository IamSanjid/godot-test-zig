//! Pure-Zig implementation of Godot's `RID` handle builtin.
//!
//! A `RID` is an opaque 64-bit engine handle. Only validity and integer-id
//! conversion belong to the math layer; ownership lives in the engine. The
//! layout is precision-independent, so this file defines the struct directly.

pub const RID = extern struct {
    id: u64 = 0,

    const Self = @This();

    pub fn init(id: u64) Self {
        return .{ .id = id };
    }

    pub fn fromUint64(id: u64) Self {
        return .{ .id = id };
    }

    pub fn isValid(self: Self) bool {
        return self.id != 0;
    }

    pub fn getId(self: Self) u64 {
        return self.id;
    }
};

test "RID layout and validity" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(RID));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(RID));

    try std.testing.expect(!RID.init(0).isValid());
    try std.testing.expect(RID.fromUint64(42).isValid());
    try std.testing.expectEqual(@as(u64, 42), RID.fromUint64(42).getId());
}

const std = @import("std");
