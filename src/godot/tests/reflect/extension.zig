//! Coverage for extension-class engine-base resolution on `godot.reflect`.
//!
//! Fake extensions over a real engine class cover compile-only classification;
//! the fake marker mirrors the annotation's structural shape without importing
//! annotations.

fn FakeMarker(comptime B: type) type {
    return struct {
        pub const BaseFor = B;

        base_ptr: *B = undefined,

        pub fn get(self: *const @This()) *B {
            return self.base_ptr;
        }

        pub fn set(self: *@This(), value: *B) void {
            self.base_ptr = value;
        }
    };
}

const EngineObject = classes.core.Object;
const EngineNode = classes.core.Node;

const DirectExtension = struct {
    pub const Extends = EngineNode;
    base: FakeMarker(Extends) = .{},
};

/// Direct extension over the root engine object class.
const DirectObjectExtension = struct {
    pub const Extends = EngineObject;
    base: FakeMarker(Extends) = .{},
};

const ChainedExtension = struct {
    pub const Extends = DirectExtension;
    base: FakeMarker(Extends) = .{},
};

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("reflect.extension: " ++ message);
}

fn comptimeChecks() void {
    check(reflect.EngineBaseType(EngineObject) == EngineObject, "an engine class is its own engine base");
    check(reflect.EngineBaseType(EngineNode) == EngineNode, "an engine class is its own engine base");
    check(reflect.EngineBaseType(DirectObjectExtension) == EngineObject, "direct extensions resolve to their engine parent");
    check(reflect.EngineBaseType(DirectExtension) == EngineNode, "direct extensions resolve to their engine parent");
    check(reflect.EngineBaseType(ChainedExtension) == EngineNode, "extension chains resolve to the ultimate engine class");
}

comptime {
    comptimeChecks();
}

test "extension base classification" {
    comptime comptimeChecks();
}

test "engineBasePointer walks extension -> extension -> engine" {
    const fake_engine: *EngineNode = @ptrFromInt(0x1000);

    var direct: DirectExtension = .{};
    direct.base.set(fake_engine);

    var chained: ChainedExtension = .{};
    chained.base.set(&direct);

    try std.testing.expectEqual(fake_engine, reflect.engineBasePointer(EngineNode, fake_engine));
    try std.testing.expectEqual(fake_engine, reflect.engineBasePointer(DirectExtension, &direct));
    try std.testing.expectEqual(fake_engine, reflect.engineBasePointer(ChainedExtension, &chained));
}

const std = @import("std");

const godot = @import("godot");
const classes = godot.classes;
const reflect = godot.reflect;
