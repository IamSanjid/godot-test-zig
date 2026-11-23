//! Compile-only coverage for `Registry` wiring and `ClassOptions`, moved out of
//! `registration/Registry.zig`.
//!
//! `addClasses` allocates, builds engine `StringName`s, and dispatches ClassDB
//! registration; the wiring function below is analyzed, never executed.

const Fixture = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    health: annotations.Property(i32, .{ .usage = .exported }) = .init(1),
};

/// Declares an `OnReady` field so the auto-OnReady notification branch is
/// analyzed as well.
const AutoOnReadyFixture = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    child: annotations.OnReady(classes.core.Node).Node("./Child"),
};

/// Nested namespace fixture for the `ClassOptions.depth` expansion path.
const Namespace = struct {
    pub const First = Fixture;
    pub const Nested = struct {
        pub const Second = Fixture;
    };
};

fn checkRegistryWiring(
    registry: *godot.Registry,
    class_registration: registration.ClassRegistration,
) void {
    // Default options: create/recreate/free/notification/property wiring for a
    // plain extension class.
    registry.addClasses(.{Fixture}, .{}, class_registration) catch {};

    // Every option that feeds the creation info: exposed/runtime flags, icon
    // path, virtual registration, auto OnReady, and property cleanup.
    registry.addClasses(.{AutoOnReadyFixture}, .{
        .auto_onready = true,
        .auto_property_cleanup = true,
        .icon_path = "res://icon.svg",
        .is_runtime = false,
        .is_virtual = true,
    }, class_registration) catch {};

    // Namespace expansion with depth > 1.
    registry.addClasses(.{Namespace}, .{ .depth = 3 }, class_registration) catch {};
}

test "ClassOptions defaults stay documented" {
    const defaults: registration.ClassOptions = .{};
    try std.testing.expect(!defaults.auto_onready);
    try std.testing.expect(!defaults.auto_property_cleanup);
    try std.testing.expect(defaults.is_exposed);
    try std.testing.expect(defaults.is_runtime);
    try std.testing.expect(defaults.icon_path == null);
    try std.testing.expect(!defaults.is_virtual);
    try std.testing.expectEqual(@as(u8, 2), defaults.depth);
}

test "Registry exposes the registration record and deinit" {
    try std.testing.expect(@hasField(godot.Registry.RegisteredClass, "creation_info"));
    try std.testing.expect(@hasField(godot.Registry.RegisteredClass, "data"));
    try std.testing.expect(@hasField(godot.Registry.RegisteredClass, "post_registration_callback"));
    try std.testing.expect(@hasDecl(godot.Registry, "addClasses"));
    try std.testing.expect(@hasDecl(godot.Registry, "deinit"));
}

test "Registry wiring analyzes classes, namespaces, and options" {
    _ = &checkRegistryWiring;
}

const std = @import("std");

const godot = @import("godot");
const annotations = godot.annotations;
const classes = godot.classes;
const registration = godot.registration;
