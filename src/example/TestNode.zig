//! Example extension class used by the generated class namespace.

pub const Extends = godot.classes.core.Node;

v: u8 = 67,
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
blah: godot.annotations.OnReady(godot.builtins.String).Call(.fromLatin1, .{"TestingString..."}),
duh: godot.annotations.OnReady(u32).Call(struct {
    fn f() u32 {
        return 69;
    }
}.f, .{}),

const TestNode = @This();

pub const Baz = godot.annotations.InitCallback(@This(), foo);
pub const BadBaz = godot.annotations.DeinitCallback(@This(), baz);

pub fn foo(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
    const variant = godot.builtins.Variant.wrap(TestNode, self);
    std.log.debug(
        "Self: {*}, Init Allocator: {}, base: {*}, p_base: {*}, v: {}, variant: {}",
        .{ self, allocator, self.base.get(), base, self.v, variant.data.object.id },
    );
}

pub fn baz(self: *@This(), allocator: std.mem.Allocator) void {
    std.log.debug(
        "Self: {*} Deinit Allocator: {}, p_base: {*}",
        .{ self, allocator, self.base.get() },
    );
    // Deinit runs from the engine base destructor. Do not call engine
    // methods on the base here; only release Zig-owned values.
    if (self.blah.getPtr()) |value| value.deinit();
    self.the_name.getPtr().deinit();
}

pub fn _ready(self: *const @This()) void {
    std.log.debug(
        "_ready was called! Self: {*}, duh: {}, the_child: {*}",
        .{ self, self.duh.get(), self.the_child.get() },
    );
    godot.utility.general.print(
        godot.builtins.Variant.wrap(godot.builtins.String, self.blah.getPtrConst()),
        .{},
    );
    godot.utility.general.print(
        godot.builtins.Variant.wrap(godot.builtins.String, self.the_name.getPtrConst()),
        .{},
    );
    if (self.child_node.value == null) return;
    std.log.debug(
        "First read!, State: {}, v: {}, child_node: {*}",
        .{ self.base.safe_guard.state, self.v, self.child_node.getPtrConst() },
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

// Compile-only coverage for the OnReady wrapper type.
comptime {
    std.debug.assert(godot.reflect.isNormalStruct(
        godot.annotations.OnReady(godot.classes.core.Node).Node("./ChildNode"),
    ));
}

const std = @import("std");

const godot = @import("godot");
