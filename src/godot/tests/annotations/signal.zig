//! `Signal` declaration discovery and typed emit coverage.

const Fixture = struct {
    pub const Extends = godot.classes.core.Node;
    /// A nested namespace with declarations is not a Signal marker.
    pub const Nested = struct {
        pub const MAX_HEALTH = 100;
    };
    pub const HealthChanged = godot.annotations.Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*godot.classes.core.Node },
    });
    pub const Pinged = godot.annotations.Signal("pinged", .{});

    pub fn methods(self: *const @This()) void {
        _ = self;
    }
};

/// A lookalike without the marker must not be discovered as a signal.
const LookalikeOwner = struct {
    pub const Lookalike = struct {
        pub const name = "pinged";
        pub const args = .{.{ "health", i32 }};
    };
};

/// A nested namespace is not a Signal marker.
const NamespaceOwner = struct {
    pub const Nested = struct {
        pub const MAX_HEALTH = 100;
    };
};

fn checkSignalDeclaration() void {
    const markers = godot.annotations.findSignals(Fixture);
    if (markers.len != 2) @compileError("findSignals must report every flat Signal declaration");
    if (!std.mem.eql(u8, markers[0].name, "health_changed")) @compileError("the engine name is the first Signal argument");
    const HealthArgs = markers[0].args;
    if (comptime HealthArgs.len != 2) @compileError("signal arguments must be preserved");
    if (!std.mem.eql(u8, HealthArgs[0][0], "health")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[0][1] != i32) @compileError("signal argument types must be preserved");
    if (!std.mem.eql(u8, HealthArgs[1][0], "source")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[1][1] != ?*godot.classes.core.Node) @compileError("object argument types must be preserved");
    if (!std.mem.eql(u8, markers[1].name, "pinged")) @compileError("argument-less signals must be discoverable");
    if (comptime markers[1].args.len != 0) @compileError("argument-less signals must report no arguments");

    if (godot.annotations.findSignals(LookalikeOwner).len != 0) @compileError("a lookalike is not a Signal marker");
    if (godot.annotations.findSignals(NamespaceOwner).len != 0) @compileError("a nested namespace is not a Signal marker");

    if (Fixture.HealthChanged.marker != godot.annotations.marker.Kind.signal)
        @compileError("Signal markers must declare marker.Kind.signal");
    if (Fixture.Pinged.marker != godot.annotations.marker.Kind.signal)
        @compileError("every Signal marker must declare marker.Kind.signal");
    if (godot.annotations.marker.kindOf(LookalikeOwner.Lookalike) != null)
        @compileError("a Signal lookalike must not declare an annotation marker");
    if (godot.annotations.marker.is(LookalikeOwner.Lookalike, .signal))
        @compileError("a Signal lookalike must not claim the signal kind");
    if (godot.annotations.marker.is(Fixture.HealthChanged, .constants))
        @compileError("Signal markers must not identify as another family");
}

/// Emit coverage: a real Base marker over a real engine class, so the owner
/// resolution and both argument forms are analyzed.
const EmitFixture = struct {
    pub const Extends = godot.classes.core.Node;
    base: godot.annotations.Base(Extends) = .{},
    pub const HealthChanged = godot.annotations.Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*godot.classes.core.Node },
    });
    pub const Pinged = godot.annotations.Signal("pinged", .{});
    /// `Variant` is the untyped argument exception: `.nil` metadata, transparent
    /// emit storage.
    pub const Anything = godot.annotations.Signal("anything", .{
        .{ "payload", godot.builtins.Variant },
    });
};

/// Custom converter argument: the declared Zig type is `Duration`; the engine
/// representation (`i32`) is derived through the conversion layer by both emit
/// and registration.
const Duration = struct {
    millis: i32,

    pub const GodotConversion = godot.annotations.Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Duration) i32 {
        return self.millis;
    }

    fn fromEngine(value: i32) Duration {
        return .{ .millis = value };
    }
};

/// Converter to an object pointer: registration must expose the engine class
/// name (`Node`) rather than the converter type's empty class name.
const NodeRef = struct {
    node: ?*godot.classes.core.Node,

    pub const GodotConversion = godot.annotations.Conversion(.{
        .engine = ?*godot.classes.core.Node,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: NodeRef) ?*godot.classes.core.Node {
        return self.node;
    }

    fn fromEngine(node: ?*godot.classes.core.Node) NodeRef {
        return .{ .node = node };
    }
};

const ConversionFixture = struct {
    pub const Extends = godot.classes.core.Node;
    base: godot.annotations.Base(Extends) = .{},
    pub const DurationChanged = godot.annotations.Signal("duration_changed", .{
        .{ "duration", Duration },
    });
    pub const NodeChanged = godot.annotations.Signal("node_changed", .{
        .{ "node", NodeRef },
    });
};

/// RefCounted argument coverage: both the raw pointer and the `Ref` converter
/// are emitted as borrowed Variant views; the caller keeps its reference alive
/// for the synchronous dispatch.
const RefCountedFixture = struct {
    pub const Extends = godot.classes.core.Node;
    base: godot.annotations.Base(Extends) = .{},
    pub const ResourceChanged = godot.annotations.Signal("resource_changed", .{
        .{ "resource", ?*godot.classes.core.Resource },
        .{ "owned", godot.ownership.Ref(godot.classes.core.Resource) },
    });
};

/// Typed container wrapper argument: a declared conversion type whose Variant
/// path registers as an Array; engine calls stay analysis-only.
const ContainerFixture = struct {
    pub const Extends = godot.classes.core.Node;
    base: godot.annotations.Base(Extends) = .{},
    pub const NumbersChanged = godot.annotations.Signal("numbers_changed", .{
        .{ "numbers", godot.collections.Array(i32) },
    });
};

fn checkEmitPath() void {
    // The registration bodies are analyzed, never executed: `StringName`
    // construction needs an initialized engine.
    _ = godot.registration.classdb.postRegistrationCallback(EmitFixture);
    _ = godot.registration.classdb.postRegistrationCallback(ConversionFixture);

    var fixture: EmitFixture = .{};
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, &fixture });
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, null });
    _ = EmitFixture.Pinged.emit(@as(*const EmitFixture, &fixture), .{});
    _ = EmitFixture.Anything.emit(@as(*const EmitFixture, &fixture), .{godot.builtins.Variant.nil});
}

/// Compile-only coverage of the declared-Zig-type conversion contract.
fn checkConversionPath() void {
    var fixture: ConversionFixture = .{};
    _ = ConversionFixture.DurationChanged.emit(&fixture, .{Duration{ .millis = 42 }});
    _ = ConversionFixture.NodeChanged.emit(&fixture, .{NodeRef{ .node = null }});

    if (comptime godot.internal.conversion.engineType(Duration) != i32)
        @compileError("a signal argument must derive its engine type through conversion");
    if (comptime godot.internal.conversion.variantType(Duration) != .int)
        @compileError("a signal argument must derive its Variant type through conversion");
    // The same contextual gate registration and emit use.
    godot.internal.conversion.checkSupported(
        Duration,
        .variant,
        "Signal 'duration_changed' argument 'duration'",
    );

    // Registration derives the class name from the converter's engine type.
    if (comptime !std.mem.eql(u8, godot.internal.conversion.engineClassName(NodeRef), "Node"))
        @compileError("a converter signal argument must expose its engine class name");
}

fn checkContainerPath() void {
    // Registration and emit bodies are analyzed, never executed.
    _ = godot.registration.classdb.postRegistrationCallback(ContainerFixture);

    var fixture: ContainerFixture = .{};
    _ = ContainerFixture.NumbersChanged.emit(&fixture, .{godot.collections.Array(i32).init()});

    // A wrapper argument is Variant-path only; its metadata follows the engine
    // container the wrapper converts to.
    const Container = godot.collections.Array(i32);
    if (comptime godot.internal.conversion.variantType(Container) != .array)
        @compileError("a wrapper signal argument must register as an Array Variant");
    godot.internal.conversion.checkSupported(Container, .variant, "Signal 'numbers_changed' argument 'numbers'");
}

fn checkRefCountedArgumentPath() void {
    // Registration and emit bodies are analyzed, never executed.
    _ = godot.registration.classdb.postRegistrationCallback(RefCountedFixture);

    var fixture: RefCountedFixture = .{};
    _ = RefCountedFixture.ResourceChanged.emit(&fixture, .{
        null,
        godot.ownership.Ref(godot.classes.core.Resource).empty,
    });
}

comptime {
    checkSignalDeclaration();
    _ = &checkEmitPath;
    _ = &checkConversionPath;
    _ = &checkContainerPath;
    _ = &checkRefCountedArgumentPath;
}

test "signals are discovered in declaration order" {
    const markers = comptime godot.annotations.findSignals(Fixture);
    try std.testing.expectEqual(@as(usize, 2), markers.len);
    try std.testing.expectEqualStrings("health_changed", markers[0].name);
    try std.testing.expectEqualStrings("pinged", markers[1].name);
}

test "converter signal arguments keep their declared Zig type" {
    const markers = comptime godot.annotations.findSignals(ConversionFixture);
    try std.testing.expectEqual(@as(usize, 2), markers.len);
    try std.testing.expectEqualStrings("duration_changed", markers[0].name);
    const args = markers[0].args;
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try std.testing.expectEqualStrings("duration", args[0][0]);
    try std.testing.expectEqual(Duration, args[0][1]);
    try std.testing.expectEqualStrings("node_changed", markers[1].name);
    try std.testing.expectEqual(NodeRef, markers[1].args[0][1]);
}

test "RefCounted signal arguments are borrowed Variant views" {
    const args = RefCountedFixture.ResourceChanged.args;
    try std.testing.expect(godot.internal.conversion.canBorrowVariant(args[0][1]));
    try std.testing.expect(godot.internal.conversion.canBorrowVariant(args[1][1]));
}

test "wrapper signal arguments expose Array Variant metadata" {
    const markers = comptime godot.annotations.findSignals(ContainerFixture);
    try std.testing.expectEqual(@as(usize, 1), markers.len);
    try std.testing.expectEqualStrings("numbers_changed", markers[0].name);
    try std.testing.expectEqual(godot.collections.Array(i32), markers[0].args[0][1]);
    try std.testing.expect(godot.internal.conversion.support(godot.collections.Array(i32)).variant);
    try std.testing.expectEqual(
        godot.bindings.interface.VariantType.array,
        godot.internal.conversion.variantType(godot.collections.Array(i32)).?,
    );
}

const std = @import("std");

const godot = @import("godot");
