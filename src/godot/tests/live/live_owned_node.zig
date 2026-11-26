//! Fixture `Node` for the live manual-ownership test.
//!
//! A `Node` is not `RefCounted`, so `godot.classes.core.Node.construct()`
//! returns `ownership.Owned(Node)`: an exclusive handle with no engine
//! reference behind it. `onInit` exercises both release paths of that handle:
//! one constructed node is destroyed in place with `Owned.deinit()` while it is
//! unparented, and a second one is handed to this fixture with `Owned.take()`
//! so the scene tree owns it from then on. `godot-test/tests/ownership.gd`
//! asserts the observable result and that the fixture frees its child.

/// Node whose `onInit` exercises the `Owned` construction and release paths.
pub const LiveOwnedNode = struct {
    pub const Extends = godot.classes.core.Node;
    pub const GodotClassName = "LiveOwnedNode";

    base: godot.annotations.Base(Extends) = .{},

    /// Instance id of the node destroyed through `Owned.deinit` (`0` when
    /// construction failed). Hidden from the inspector but readable from
    /// GDScript, which resolves it to confirm the object is really gone.
    destroyed_id: godot.annotations.Property(i64, .{
        .usage = .no_editor,
    }) = .init(0),

    pub const OnInit = godot.annotations.InitCallback(@This(), onInit);

    pub fn onInit(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
        _ = allocator;

        // Exclusive manual ownership, destroyed in place: `deinit` calls
        // `Object.destroy`, so the unparented node is freed right here.
        var scratch = godot.classes.core.Node.construct();
        if (scratch.get()) |scratch_ptr| {
            self.destroyed_id.value = @intCast(scratch_ptr.upcast(godot.classes.core.Object).getInstanceId());
            scratch.deinit();
            std.debug.assert(scratch.isNull());
        }

        // Exclusive manual ownership, handed off: `take` empties the handle
        // and this fixture becomes the child's owner, so the child lives and
        // dies with the fixture.
        var child = godot.classes.core.Node.construct();
        if (child.take()) |child_ptr| {
            child_ptr.setName(godot.builtins.StringName.fromComptimeLatin1("owned_child"));
            base.addChild(child_ptr, .{});
        }
    }
};

const std = @import("std");

const godot = @import("godot");
