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
        .set = .best_effort,
        .deinit = .best_effort,
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

    /// Emitted from `_ready` with borrowed `String`, `Array`, and `Variant`
    /// arguments plus an owned heap-builtin `Transform3D`.
    pub const Signaled = godot.annotations.Signal("signaled", .{
        .{ "text", godot.builtins.String },
        .{ "numbers", godot.builtins.Array },
        .{ "payload", godot.builtins.Variant },
        .{ "transform", godot.builtins.Transform3D },
        .{ "count", i32 },
    });

    /// Emits `Signaled` while entering the tree; the GDScript suite connects
    /// before `add_child` and checks the delivered values.
    pub fn _ready(self: *const @This()) void {
        var text = godot.builtins.String.fromLatin1("borrowed");
        defer text.deinit();

        var numbers = godot.builtins.Array.init();
        defer numbers.deinit();
        numbers.append(godot.builtins.Variant.borrow(i32, @as(i32, 5)).get());
        numbers.append(godot.builtins.Variant.borrow(i32, @as(i32, 6)).get());

        var payload = godot.builtins.Variant.init(i32, 42);
        defer payload.deinit();

        _ = Signaled.emit(self, .{
            text,
            numbers,
            payload,
            godot.builtins.Transform3D.identity,
            7,
        });
    }

    pub const ConstantsDecl = godot.annotations.Constants(struct {
        pub const MAX_HEALTH: i32 = 100;
        pub const Mode = enum(i32) { idle, running = 3 };
    });
};

const godot = @import("godot");
