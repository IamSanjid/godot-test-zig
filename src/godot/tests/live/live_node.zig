//! Fixture class for the headless live test.
//!
//! Add one fixture class per `.zig` file and register it in `entrypoint.zig`.
//! The matching GDScript assertions live under `godot-test/tests/`.

/// Node registered for the headless live test; see `godot-test/run_tests.gd`.
pub const LiveNode = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},

    health: godot.annotations.Property(i32, .{
        .usage = .exported,
        .hint = .range,
        .hint_string = "0,100",
    }) = .init(100),
    label: godot.annotations.Property(godot.builtins.String, .{
        .usage = .exported,
    }).Init(.fromLatin1, .{"live"}),
    mode: godot.annotations.Property(ConstantsDecl.decls.Mode, .{
        .usage = .exported,
    }) = .init(.idle),

    /// Inspector sections for every visible `Property` field, each listed once.
    pub const Groups = godot.annotations.PropertyGroups(.{
        .{ .name = "Live", .fields = .{ "health", "label", "mode" } },
    });

    pub const Pinged = godot.annotations.Signal("pinged", .{
        .{ "health", i32 },
    });

    pub const ConstantsDecl = godot.annotations.Constants(struct {
        pub const MAX_HEALTH: i32 = 100;
        pub const Mode = enum(i32) { idle, running = 3 };
    });
};

const godot = @import("godot");
