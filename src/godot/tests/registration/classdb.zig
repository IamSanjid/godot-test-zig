//! Compile-only coverage for class-level ClassDB registration (constants and
//! signals), moved from `registration/classdb.zig`.
//!
//! The runtime registration calls below are analyzed, never executed: the
//! engine must be initialized before `StringName` construction.

const Fixture = struct {
    pub const HealthChanged = annotations.Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*classes.core.Node },
    });
    pub const Pinged = annotations.Signal("pinged", .{});

    pub const ClassConstants = annotations.Constants(struct {
        pub const MAX_HEALTH = 100;
        pub const State = enum(i32) { idle, running = 3 };
        pub const Flags = bitpack struct(u32) {
            first: bool = false,
            _pad0: u31 = 0,
        };
    });
};

/// A class with no class-level metadata must not build a callback.
const NoSurface = struct {};

/// Instantiates constant and signal registration for `Fixture`. Never called:
/// both paths construct engine `StringName`s.
fn checkRegistrationPaths() void {
    _ = classdb.postRegistrationCallback(Fixture);
}

test "a class without class-level metadata gets no post-registration callback" {
    comptime {
        if (classdb.postRegistrationCallback(NoSurface) != null) {
            @compileError("a class without signals/constants must get no post-registration callback");
        }
    }
}

test "class constants and signals get a post-registration callback" {
    comptime {
        if (classdb.postRegistrationCallback(Fixture) == null) {
            @compileError("a class with signals/constants must get a post-registration callback");
        }
    }
    _ = &checkRegistrationPaths;
}

const godot = @import("godot");
const annotations = godot.annotations;
const classdb = godot.registration.classdb;
const classes = godot.classes;
