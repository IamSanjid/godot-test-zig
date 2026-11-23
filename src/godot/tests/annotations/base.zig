//! `Base` marker discovery and construction through the public facade.
//!
//! Discovery itself is annotation-free (`godot.reflect`); these checks pin the
//! contract that `annotations.Base` markers stay discoverable there because
//! `Variant` and registration use that layer.

const TestParent = struct { value: u32 = 0 };

const TestExtension = struct {
    base: godot.annotations.Base(TestParent) = .{},
};

fn checkAnnotationMarker() void {
    const field = godot.reflect.findBaseFieldFor(TestExtension, TestParent) orelse
        @compileError("annotations.Base marker is not discoverable by reflect.base");
    if (field.base_type != TestParent) @compileError("reflect.base reports the wrong Base marker parent type");
    if (!std.mem.eql(u8, field.name, "base")) @compileError("reflect.base reports the wrong Base marker field name");
    if (!godot.annotations.marker.is(@FieldType(TestExtension, "base"), .base))
        @compileError("annotations.Base must declare marker.Kind.base");
}

comptime {
    checkAnnotationMarker();
}

test "reflect.base discovers annotations.Base markers" {
    comptime checkAnnotationMarker();

    var parent: TestParent = .{};
    var extension: TestExtension = .{};
    extension.base.set(&parent);

    const pointer = godot.reflect.basePointer(TestExtension, TestParent, &extension);
    try std.testing.expect(pointer != null);
    try std.testing.expectEqual(&parent, pointer.?);
}

test "initBase stores the engine base pointer" {
    var parent: TestParent = .{ .value = 7 };
    var extension: TestExtension = .{};
    godot.annotations.initBase(TestExtension, TestParent, &extension, &parent);

    const pointer = godot.reflect.basePointer(TestExtension, TestParent, &extension);
    try std.testing.expect(pointer != null);
    try std.testing.expectEqual(&parent, pointer.?);
}

const std = @import("std");

const godot = @import("godot");
