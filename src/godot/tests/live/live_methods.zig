//! Fixture `Node` for the live engine-method test.
//!
//! One method per adapter shape: instance and const instance methods, a static
//! method, scalar arguments and returns, a managed `String` result, borrowed and
//! owned `RefCounted` results, an untyped `Variant`, and a local converter
//! argument. `godot-test/tests/methods.gd` calls each through a statically typed
//! variable (the validated ptrcall path) and through `Object.call`/`Callable`
//! (the Variant path).

/// Node whose registered methods exercise both method call paths.
pub const LiveMethods = struct {
    pub const Extends = godot.classes.core.Node;
    pub const GodotClassName = "LiveMethods";

    base: godot.annotations.Base(Extends) = .{},

    /// Engine resource owned by the fixture and hidden from the engine property
    /// list; `make_resource` lends it out as a borrowed raw pointer.
    resource: godot.annotations.Property(ResourceRef, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(ResourceRef.empty),

    pub const RegMethods = godot.annotations.Methods(.{
        godot.annotations.Method(.add, .{ .arg_names = .{ "a", "b" } }),
        godot.annotations.Method(.label, .{}),
        godot.annotations.Method(.version, .{ .is_static = true }),
        godot.annotations.Method(.makeResource, .{}),
        godot.annotations.Method(.makeOwnedResource, .{}),
        godot.annotations.Method(.echoVariant, .{ .arg_names = .{"value"} }),
        godot.annotations.Method(.shift, .{ .arg_names = .{"duration"} }),
    });

    pub const OnInit = godot.annotations.InitCallback(@This(), onInit);
    pub const OnDeinit = godot.annotations.DeinitCallback(@This(), onDeinit);

    /// Creates the resource that `make_resource` lends out.
    pub fn onInit(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
        _ = allocator;
        _ = base;
        self.resource.value = godot.classes.core.Resource.construct();
    }

    /// Releases the owned resource through the field's `.best_effort` cleanup.
    pub fn onDeinit(self: *@This(), allocator: std.mem.Allocator) void {
        _ = allocator;
        godot.annotations.deinitPropertyFields(@This(), self);
    }

    /// Plain scalar instance method.
    pub fn add(self: *@This(), a: i32, b: i32) i32 {
        _ = self;
        return a + b;
    }

    /// Const method returning a fresh managed `String`: the Variant adapter
    /// releases the result it copied into the return Variant, while the ptrcall
    /// adapter moves it into the engine slot.
    pub fn label(self: *const @This()) godot.builtins.String {
        _ = self;
        return godot.builtins.String.fromLatin1("live_methods");
    }

    /// Static method: the engine passes a null instance and the adapter must not
    /// decode one.
    pub fn version() i32 {
        return 7;
    }

    /// Borrowed raw `RefCounted` result: the `resource` field owns the only
    /// reference; the engine return slot and GDScript Variant take their own.
    pub fn makeResource(self: *@This()) ?*godot.classes.core.Resource {
        return self.resource.value.get();
    }

    /// Owned `RefCounted` result: the adapter releases this wrapper after the
    /// engine keeps its own reference.
    pub fn makeOwnedResource(self: *@This()) ResourceRef {
        _ = self;
        return godot.classes.core.Resource.construct();
    }

    /// Untyped `Variant` argument and result; both are owned decodes.
    pub fn echoVariant(self: *@This(), value: godot.builtins.Variant) godot.builtins.Variant {
        _ = self;
        return value.clone();
    }

    /// Local converter argument: both adapters decode an engine `i32` through
    /// `fromEngine` and release the decoded `Duration`.
    pub fn shift(self: *@This(), duration: Duration) i32 {
        _ = self;
        return duration.millis + 1;
    }

    /// Engine representation is a scalar, so it supports both paths.
    pub const Duration = struct {
        millis: i32,

        pub const GodotConversion = godot.annotations.Conversion(.{
            .engine = i32,
            .to_engine = toEngine,
            .from_engine = fromEngine,
        });

        fn toEngine(self: Duration) i32 {
            return self.millis;
        }

        fn fromEngine(millis: i32) Duration {
            return .{ .millis = millis };
        }
    };
};

const std = @import("std");

const godot = @import("godot");

const ResourceRef = godot.ownership.Ref(godot.classes.core.Resource);
