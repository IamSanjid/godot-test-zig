//! Pure-Zig implementation of Godot's `RID` handle builtin.
//!
//! A `RID` is an opaque 64-bit engine handle. Only validity and integer-id
//! conversion belong to the math layer; ownership lives in the engine. The
//! layout is precision-independent, so this file defines the struct directly.

pub const RID = extern struct {
    id: u64 = 0,

    const Self = @This();

    pub inline fn toBinding(self: *const Self) bindings.builtins.RID {
        return @as(*const bindings.builtins.RID, @ptrCast(self)).*;
    }

    pub inline fn fromBinding(v: anytype) Self {
        const V = @TypeOf(v);
        return switch (V) {
            *bindings.builtins.RID => @as(*const Self, @ptrCast(v)).*,
            *const bindings.builtins.RID => @as(*const Self, @ptrCast(v)).*,
            bindings.builtins.RID => @as(*const Self, @ptrCast(&v)).*,
            else => @compileError("Expected bindings.builtins.RID by value or a pointer to it, found: " ++ @typeName(V)),
        };
    }

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
const bindings = @import("bindings");
