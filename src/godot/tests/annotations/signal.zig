//! `Signal` declaration discovery and typed emit coverage.

const Fixture = struct {
    pub const Extends = godot.classes.core.Node;
    /// A nested namespace with declarations is not a Signal marker.
    pub const Nested = struct {
        pub const MAX_HEALTH = 100;
    };
    pub const HealthChanged = godot.annotations.Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*godot.classes.core.Node },
    });
    pub const Pinged = godot.annotations.Signal("pinged", .{});

    pub fn methods(self: *const @This()) void {
        _ = self;
    }
};

/// A lookalike without the marker must not be discovered as a signal.
const LookalikeOwner = struct {
    pub const Lookalike = struct {
        pub const name = "pinged";
        pub const args = .{.{ "health", i32 }};
    };
};

/// A nested namespace is not a Signal marker.
const NamespaceOwner = struct {
    pub const Nested = struct {
        pub const MAX_HEALTH = 100;
    };
};

fn checkSignalDeclaration() void {
    const markers = godot.annotations.findSignals(Fixture);
    if (markers.len != 2) @compileError("findSignals must report every flat Signal declaration");
    if (!std.mem.eql(u8, markers[0].name, "health_changed")) @compileError("the engine name is the first Signal argument");
    const HealthArgs = markers[0].args;
    if (comptime HealthArgs.len != 2) @compileError("signal arguments must be preserved");
    if (!std.mem.eql(u8, HealthArgs[0][0], "health")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[0][1] != i32) @compileError("signal argument types must be preserved");
    if (!std.mem.eql(u8, HealthArgs[1][0], "source")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[1][1] != ?*godot.classes.core.Node) @compileError("object argument types must be preserved");
    if (!std.mem.eql(u8, markers[1].name, "pinged")) @compileError("argument-less signals must be discoverable");
    if (comptime markers[1].args.len != 0) @compileError("argument-less signals must report no arguments");

    if (godot.annotations.findSignals(LookalikeOwner).len != 0) @compileError("a lookalike is not a Signal marker");
    if (godot.annotations.findSignals(NamespaceOwner).len != 0) @compileError("a nested namespace is not a Signal marker");
}

/// Emit coverage: a real Base marker over a real engine class, so the owner
/// resolution and both argument forms are analyzed.
const EmitFixture = struct {
    pub const Extends = godot.classes.core.Node;
    base: godot.annotations.Base(Extends) = .{},
    pub const HealthChanged = godot.annotations.Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*godot.classes.core.Node },
    });
    pub const Pinged = godot.annotations.Signal("pinged", .{});
};

fn checkEmitPath() void {
    var fixture: EmitFixture = .{};
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, &fixture });
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, null });
    _ = EmitFixture.Pinged.emit(@as(*const EmitFixture, &fixture), .{});
}

comptime {
    checkSignalDeclaration();
    _ = &checkEmitPath;
}

test "signals are discovered in declaration order" {
    const markers = comptime godot.annotations.findSignals(Fixture);
    try std.testing.expectEqual(@as(usize, 2), markers.len);
    try std.testing.expectEqualStrings("health_changed", markers[0].name);
    try std.testing.expectEqualStrings("pinged", markers[1].name);
}

const std = @import("std");

const godot = @import("godot");
