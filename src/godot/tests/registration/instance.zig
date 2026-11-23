//! Compile-only coverage for the extension-class instance lifecycle callbacks
//! (create, hot-reload recreate, free), moved from `registration/instance.zig`.
//!
//! The callbacks contain engine calls; they are analyzed, never executed.

/// Initializer covers both pointer placeholders: `owner` is the extension
/// instance and `base` is the engine base.
fn seededHealth(owner: *InitPropertyOwner, base: *classes.core.Node) i32 {
    _ = owner;
    _ = base;
    return 100;
}

const InitPropertyOwner = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    health: annotations.Property(i32, .{
        .usage = .exported,
        .init = annotations.Init(i32, seededHealth, .{ .owner, .base }),
    }) = .init(0),
};

fn checkCreate() void {
    _ = &registration.CreateInstance(InitPropertyOwner, InitPropertyOwner.Extends);
}

fn checkRecreate() void {
    _ = &registration.RecreateInstance(InitPropertyOwner, InitPropertyOwner.Extends);
}

fn checkFree() void {
    _ = &registration.FreeInstance(InitPropertyOwner, InitPropertyOwner.Extends, false);
    _ = &registration.FreeInstance(InitPropertyOwner, InitPropertyOwner.Extends, true);
}

test "create-instance callback builds the shared initialization sequence" {
    comptime {
        if (!godot.reflect.isEngineObjectClass(InitPropertyOwner.Extends)) {
            @compileError("the create-instance fixture must extend an instantiable engine class");
        }
    }
    _ = &checkCreate;
}

test "recreate-instance callback reuses the create sequence" {
    _ = &checkRecreate;
}

test "free-instance callback covers both property cleanup modes" {
    _ = &checkFree;
}

const godot = @import("godot");
const annotations = godot.annotations;
const classes = godot.classes;
const registration = godot.registration;
