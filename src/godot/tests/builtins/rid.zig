//! Tests for the pure-Zig `RID` builtin.

test "RID layout and validity" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(RID));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(RID));

    try std.testing.expect(!RID.init(0).isValid());
    try std.testing.expect(RID.fromUint64(42).isValid());
    try std.testing.expectEqual(@as(u64, 42), RID.fromUint64(42).getId());
}

const std = @import("std");

const godot = @import("godot");
const RID = godot.builtins.RID;
