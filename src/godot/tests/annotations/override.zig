//! `Override` declaration marker identity and discovery through virtual
//! registration (`registration.virtuals.collect` uses `findOverrideDecls`).

fn lookalikeOverride() void {}

const Fixture = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},

    pub const Ready = godot.annotations.Override("_ready", ready);

    /// Same payload declarations as an override, but no marker kind. If this
    /// were discovered, `collect` would try to validate `_process` against a
    /// no-argument function and fail to compile.
    pub const Lookalike = struct {
        pub const godot_virtual_method = "_process";
        pub const override_with = lookalikeOverride;
    };

    fn ready(self: *@This()) void {
        _ = self;
    }
};

fn checkOverrideMarker() void {
    if (comptime Fixture.Ready.marker != godot.annotations.marker.Kind.override)
        @compileError("Override markers must declare marker.Kind.override");
    if (comptime !godot.annotations.marker.is(Fixture.Ready, .override))
        @compileError("Override markers must identify as the override family");
    if (comptime godot.annotations.marker.kindOf(Fixture.Lookalike) != null)
        @compileError("an Override lookalike must not declare an annotation marker");

    const entries = comptime godot.registration.virtuals.collect(Fixture, Fixture.Extends);
    if (entries.len != 1) @compileError("virtual registration must discover exactly the marker-backed override");
    if (!std.mem.eql(u8, entries[0].name, "_ready"))
        @compileError("virtual registration must report the override's virtual method");
    if (!std.mem.eql(u8, entries[0].godot_name, "_ready"))
        @compileError("virtual registration must use the engine virtual name");
}

comptime {
    checkOverrideMarker();
}

test "Override marker identity feeds virtual registration" {
    comptime checkOverrideMarker();
}

const std = @import("std");

const godot = @import("godot");
