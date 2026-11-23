//! Coverage for the generic `godot.reflect` meta helpers.

test "isOptionalPointer accepts single-item pointer optionals only" {
    try std.testing.expect(reflect.isOptionalPointer(?*u32));
    try std.testing.expect(reflect.isOptionalPointer(?*const u32));
    try std.testing.expect(reflect.isOptionalPointer(?*anyopaque));
    try std.testing.expect(!reflect.isOptionalPointer(*u32));
    try std.testing.expect(!reflect.isOptionalPointer(*const u32));
    try std.testing.expect(!reflect.isOptionalPointer(u32));
    try std.testing.expect(!reflect.isOptionalPointer(?u32));
    try std.testing.expect(!reflect.isOptionalPointer(?[*]u32));
    try std.testing.expect(!reflect.isOptionalPointer(?[*:0]u32));
    try std.testing.expect(!reflect.isOptionalPointer(?[]u32));
}

const std = @import("std");

const godot = @import("godot");
const reflect = godot.reflect;
