pub const std_options: std.Options = .{
    .logFn = godot.richLogFn,
};

pub const TestNode = struct {
    pub const Extends = godot.classes.core.Node;
    v: u8 = 67,
    base: godot.annotations.Base(Extends) = .{},
    child_node: godot.annotations.OnReady(godot.classes.core.Node, .{ .node = "./ChildNode" }),
    blah: godot.annotations.OnReady(godot.builtins.String, .{ .call = .{ .fromLatin1, .{"TestingString..."} } }),
    duh: godot.annotations.OnReady(u32, .{
        .call = .{struct {
            fn f() u32 {
                return 69;
            }
        }.f},
    }),

    pub const Baz = godot.annotations.InitCallback(@This(), foo);
    pub const BadBaz = godot.annotations.DeinitCallback(@This(), baz);

    pub fn foo(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
        std.log.debug(
            "Self: {*}, Init Allocator: {}, base: {*}, p_base: {*}, v: {}",
            .{ self, allocator, self.base.get(), base, self.v },
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
    }

    pub const PhysicsProcessOverride = godot.annotations.Override("_physics_process", iam_lazy);

    fn iam_lazy(self: *@This(), delta: f64) void {
        _ = self;
        std.log.debug("_physics_process: {}", .{delta});
    }

    pub fn _ready(self: *const @This()) void {
        std.log.debug("_ready was called! Self: {*}, duh: {}", .{ self, self.duh.get() });
        godot.utility.general.print(godot.builtins.Variant.fromPtr(godot.builtins.String, &self.blah.get()), .{});
        if (self.child_node.value == null) return;
        std.log.debug(
            "First read!, State: {}, v: {}, child_node: {*}",
            .{ self.base._safe_guard._state, self.v, self.child_node.getPtrConst() },
        );
        const fmt: godot.builtins.StringName = .fromComptimeLatin1("ChildNode: ");
        godot.utility.general.print(
            godot.builtins.Variant.fromPtr(godot.builtins.StringName, &fmt),
            .{
                godot.builtins.Variant.fromPtr(
                    godot.classes.core.Object,
                    @as(*godot.classes.core.Object, @ptrCast(self.child_node.get())),
                ),
            },
        );
    }

    comptime {
        std.debug.assert(godot.reflect.isNormalStruct(godot.annotations.OnReady(godot.classes.core.Node, .{ .node = "./ChildNode" })));
    }
};

export fn test_zig_init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    if (!godot.init(godot.engine_allocator, get_proc_address, library, initialization)) return false;

    var godot_version: gdi.GodotVersion2 = .{};
    godot.dispatch(.get_godot_version2, .{&godot_version});
    if (godot_version.major != 4 or
        godot_version.minor < 8)
    {
        std.log.err("Need at least 4.8 godot.", .{});
        return false;
    }

    const TestNode2 = struct {
        pub const Extends = godot.classes.core.Node;
        v: u8 = 0,

        pub fn _ready(_: *const @This()) void {
            std.log.debug("Second read!", .{});
        }
    };

    godot.registry().addClasses(
        .{ @This(), TestNode2 },
        .{ .auto_onready = true },
        .{ .create_allocator = godot.engine_allocator },
    ) catch return false;

    return true;
}

const std = @import("std");

const godot = @import("godot");
const gdi = godot.bindings.interface;
