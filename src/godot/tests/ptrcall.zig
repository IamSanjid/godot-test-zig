//! Direct ptrcall slot primitives: type dispatch and slot width.
//!
//! Compile-only analysis covers the object and extension dispatch; the runtime
//! test only touches an integer slot, which needs no engine.

/// Extension class used to analyze engine-base resolution in ptrcall slots.
const ExtensionNode = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},
};

fn analyzeDispatch() void {
    ptrcall.encodeDirectPtr(i32, undefined, null);
    _ = ptrcall.decodeDirectPtr(i32, null);
    ptrcall.encodeDirectPtr(?*godot.classes.core.Node, null, null);
    _ = ptrcall.decodeDirectPtr(*godot.classes.core.Node, null);
    ptrcall.encodeDirectPtr(?*godot.classes.core.RefCounted, null, null);
    _ = ptrcall.decodeDirectPtr(?*godot.classes.core.RefCounted, null);
    ptrcall.encodeDirectPtr(?*ExtensionNode, null, null);
    ptrcall.encodeDirectPtr(*ExtensionNode, undefined, null);
    _ = ptrcall.decodeDirectPtr(?*ExtensionNode, null);
}

comptime {
    _ = &analyzeDispatch;
}

test "integer slot round-trips" {
    var slot: i64 = 0;
    ptrcall.encodeDirectPtr(i32, -3, @ptrCast(&slot));
    try std.testing.expectEqual(@as(i32, -3), ptrcall.decodeDirectPtr(i32, @ptrCast(&slot)));
}

const std = @import("std");

const godot = @import("godot");
const ptrcall = godot.internal.ptrcall;
