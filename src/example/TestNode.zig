//! Example extension class used by the generated class namespace.

pub const Extends = godot.classes.core.Node;

/// A plain field with no annotation; registration leaves it alone.
unannotated: u8 = 67,
health: godot.annotations.Property(i32, .{
    .usage = .exported,
    .hint = .range,
    .hint_string = "0,100",
}) = .init(100),
the_child: godot.annotations.Property(?*godot.classes.core.Node, .{
    .usage = .exported,
    .hint = .node_type,
    .hint_string = "Node",
}) = .init(null),
the_name: godot.annotations.Property(godot.builtins.String, .{
    .usage = .exported,
}).Init(.fromLatin1, .{"TheName!"}),
base: godot.annotations.Base(Extends) = .{},
child_node: godot.annotations.OnReady(godot.classes.core.Node).Node("./ChildNode"),
label: godot.annotations.OnReady(godot.builtins.String).Call(.fromLatin1, .{"TestingString..."}),
answer: godot.annotations.OnReady(u32).Call(struct {
    fn f() u32 {
        return 69;
    }
}.f, .{}),

const TestNode = @This();

/// Signals registered with this class. See docs/signals.md.
pub const HealthChanged = godot.annotations.Signal("health_changed", .{
    .{ "health", i32 },
    .{ "source", ?*godot.classes.core.Node },
});
pub const Pinged = godot.annotations.Signal("pinged", .{});

pub const ClassConstants = godot.annotations.Constants(struct {
    pub const MAX_HEALTH: i32 = 100;
    pub const State = enum(i32) { idle, running = 3 };
    pub const Flags = bitpack struct(u32) {
        first: bool = false,
        second: bool = false,
        _pad0: u30 = 0,
    };
});

pub const OnInit = godot.annotations.InitCallback(@This(), onInit);
pub const OnDeinit = godot.annotations.DeinitCallback(@This(), onDeinit);

pub fn onInit(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
    const variant = godot.builtins.Variant.wrap(TestNode, self);
    std.log.debug(
        "onInit: self {*}, allocator {}, base {*}, p_base {*}, unannotated {}, object id {}",
        .{ self, allocator, base, self.base.get(), self.unannotated, variant.data.object.id },
    );
}

pub fn onDeinit(self: *@This(), allocator: std.mem.Allocator) void {
    std.log.debug("onDeinit: self {*}, allocator {}, p_base {*}", .{ self, allocator, self.base.get() });
    // Deinit runs from the engine base destructor: do not call engine methods on
    // the base here, only release Zig-owned values.
    if (self.label.getPtr()) |value| value.deinit();
    self.the_name.getPtr().deinit();
}

pub fn _ready(self: *const @This()) void {
    std.log.debug(
        "_ready: self {*}, answer {}, child_node {*}",
        .{ self, self.answer.get(), self.the_child.get() },
    );
    _ = TestNode.HealthChanged.emit(self, .{ self.health.get(), self });
    _ = TestNode.Pinged.emit(self, .{});
    godot.utility.general.print(
        godot.builtins.Variant.wrap(godot.builtins.String, self.label.getPtrConst()),
        .{},
    );
    godot.utility.general.print(
        godot.builtins.Variant.wrap(godot.builtins.String, self.the_name.getPtrConst()),
        .{},
    );
    // Defensive: auto OnReady already resolved this on post-enter-tree.
    if (self.child_node.value == null) return;
    std.log.debug(
        "first read: state {}, unannotated {}, child_node {*}",
        .{ self.base.safe_guard.state, self.unannotated, self.child_node.getPtrConst() },
    );
    const fmt: godot.builtins.StringName = .fromComptimeLatin1("ChildNode: ");
    godot.utility.general.print(
        godot.builtins.Variant.wrap(godot.builtins.StringName, &fmt),
        .{
            godot.builtins.Variant.wrap(
                godot.classes.core.Object,
                @as(*godot.classes.core.Object, @ptrCast(self.child_node.get())),
            ),
        },
    );
}

const std = @import("std");

const godot = @import("godot");
