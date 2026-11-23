//! Contract checks and compile-only coverage for `godot.conversion`.
//!
//! Compile-only analysis instantiates every encode/decode primitive; the runtime
//! tests only touch scalar Variant and ptrcall slots, which need no engine
//! initialization.

/// Scalar engine type; both conversion functions are exercised by the analysis
/// and by the scalar runtime round-trips below.
const Duration = struct {
    millis: i32,

    pub const GodotConversion = Conversion(.{
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

/// Builtin engine type.
const Label = struct {
    value: godot.builtins.String,

    pub const GodotConversion = Conversion(.{
        .engine = godot.builtins.String,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Label) godot.builtins.String {
        return godot.builtins.String.fromString(self.value);
    }

    fn fromEngine(value: godot.builtins.String) Label {
        return .{ .value = godot.builtins.String.fromString(value) };
    }
};

/// Optional non-RefCounted object-pointer engine type.
const NodeRef = struct {
    node: ?*godot.classes.core.Node,

    pub const GodotConversion = Conversion(.{
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

/// Optional RefCounted engine type; exercises the `ref_get_object`/
/// `ref_set_object` ptrcall branch through a converter.
const ResourceRef = struct {
    value: ?*godot.classes.core.RefCounted,

    pub const GodotConversion = Conversion(.{
        .engine = ?*godot.classes.core.RefCounted,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: ResourceRef) ?*godot.classes.core.RefCounted {
        return self.value;
    }

    fn fromEngine(value: ?*godot.classes.core.RefCounted) ResourceRef {
        return .{ .value = value };
    }
};

/// Extension class used to analyze engine-base resolution in ptrcall paths.
const ExtensionNode = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},
};

/// Virtual fixture with raw-pointer parameters; this is the shape generated
/// virtuals use for buffers and optional opaque pointers.
const PacketPeer = struct {
    pub const Extends = godot.classes.core.PacketPeerExtension;

    base: godot.annotations.Base(Extends) = .{},

    pub fn _getAvailablePacketCount(_: *const @This()) i32 {
        return 0;
    }

    pub fn _getMaxPacketSize(_: *const @This()) i32 {
        return 0;
    }

    pub fn _getPacket(_: *@This(), _: ?*anyopaque, _: *i32) godot.enums.Error {
        return .ok;
    }

    pub fn _putPacket(_: *@This(), _: *u8, _: i32) godot.enums.Error {
        return .ok;
    }
};

const Plain = struct {
    value: u32 = 0,
};

/// Compile-only property integration: the property backend must use the
/// converter's engine type instead of `Variant.typeFor(Duration)`.
const DurationOwner = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},
    duration: godot.annotations.Property(Duration, .{
        .usage = .exported,
    }) = .init(.{ .millis = 1 }),
};

/// Object-engine converter; exercises property-list class-name derivation.
const NodeRefOwner = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},
    node: godot.annotations.Property(NodeRef, .{
        .usage = .exported,
    }) = .init(.{ .node = null }),
};

fn analyzePropertyBackend() void {
    _ = godot.registration.property.callbacks(DurationOwner);
    _ = godot.registration.property.callbacks(NodeRefOwner);
    _ = godot.registration.property.propertyInfoList(DurationOwner);
    _ = godot.registration.property.propertyInfoList(NodeRefOwner);
}

fn analyzeVirtuals() void {
    _ = comptime godot.registration.virtuals.collect(PacketPeer, PacketPeer.Extends);
}

fn expectSupport(comptime T: type, comptime variant: bool, comptime ptr: bool) void {
    const actual = comptime conversion.support(T);
    if (actual.variant != variant or actual.ptr != ptr) {
        @compileError("Unexpected conversion support for " ++ @typeName(T));
    }
}

fn expectEngineType(comptime T: type, comptime Expected: type) void {
    const actual = comptime conversion.engineType(T) orelse
        @compileError("Expected an engine type for " ++ @typeName(T));
    if (actual != Expected) @compileError("Unexpected engine type for " ++ @typeName(T));
}

fn expectNoEngineType(comptime T: type) void {
    if (comptime conversion.engineType(T) != null) {
        @compileError("Expected no engine type for " ++ @typeName(T));
    }
}

fn expectVariantType(comptime T: type, comptime Expected: ?interface.VariantType) void {
    if (comptime conversion.variantType(T) != Expected) {
        @compileError("Unexpected Variant type for " ++ @typeName(T));
    }
}

fn checkContract() void {
    @setEvalBranchQuota(1_000_000);
    // Direct support: scalars, builtins, Variant, and object pointers.
    expectSupport(i32, true, true);
    expectSupport(f64, true, true);
    expectSupport(bool, true, true);
    expectSupport(godot.builtins.String, true, true);
    expectSupport(godot.builtins.Vector2, true, true);
    expectSupport(godot.builtins.Variant, true, true);
    expectSupport(*godot.classes.core.Node, true, true);
    expectSupport(*const godot.classes.core.Node, true, true);
    expectSupport(?*godot.classes.core.Node, true, true);
    expectSupport(?*godot.classes.core.RefCounted, true, true);
    expectSupport(*i32, false, true);
    expectSupport(*u8, false, true);
    expectSupport(?*anyopaque, false, true);

    // Custom support follows a valid marker's directly supported engine type.
    expectSupport(Duration, true, true);
    expectSupport(Label, true, true);
    expectSupport(NodeRef, true, true);
    expectSupport(ResourceRef, true, true);
    expectSupport(*ExtensionNode, true, true);
    expectSupport(?*ExtensionNode, true, true);

    // `void` is not a value type; unsupported scalar widths, plain structs, and
    // bare class types (which must be used as pointers) have no conversion.
    expectSupport(void, false, false);
    expectSupport(i128, false, false);
    expectSupport(Plain, false, false);
    expectSupport([*]u8, false, false);
    expectSupport(godot.classes.core.Node, false, false);
    expectSupport(godot.classes.core.RefCounted, false, false);

    expectEngineType(i32, i32);
    expectEngineType(godot.builtins.String, godot.builtins.String);
    expectEngineType(godot.builtins.Variant, godot.builtins.Variant);
    expectEngineType(*godot.classes.core.Node, *godot.classes.core.Node);
    expectEngineType(?*godot.classes.core.Node, ?*godot.classes.core.Node);
    expectEngineType(*i32, *i32);
    expectEngineType(?*anyopaque, ?*anyopaque);
    expectEngineType(Duration, i32);
    expectEngineType(Label, godot.builtins.String);
    expectEngineType(NodeRef, ?*godot.classes.core.Node);
    expectEngineType(ResourceRef, ?*godot.classes.core.RefCounted);
    expectEngineType(*ExtensionNode, *ExtensionNode);
    expectEngineType(?*ExtensionNode, ?*ExtensionNode);

    expectNoEngineType(void);
    expectNoEngineType(i128);
    expectNoEngineType(Plain);

    expectVariantType(i32, .int);
    expectVariantType(f64, .float);
    expectVariantType(bool, .bool);
    expectVariantType(godot.builtins.String, .string);
    expectVariantType(godot.builtins.Vector2, .vector2);
    expectVariantType(*godot.classes.core.Node, .object);
    expectVariantType(?*godot.classes.core.Node, .object);
    expectVariantType(?*godot.classes.core.RefCounted, .object);
    expectVariantType(*i32, null);
    expectVariantType(?*anyopaque, null);
    expectVariantType(godot.builtins.Variant, null);
    expectVariantType(Duration, .int);
    expectVariantType(Label, .string);
    expectVariantType(NodeRef, .object);
    expectVariantType(ResourceRef, .object);
    expectVariantType(*ExtensionNode, .object);
    expectVariantType(?*ExtensionNode, .object);
    expectVariantType(void, null);
    expectVariantType(Plain, null);

    // Valid types must pass the contextual gates without errors.
    conversion.checkSupported(i32, .variant, "test scalar variant");
    conversion.checkSupported(i32, .ptr, "test scalar ptr");
    conversion.checkSupported(*i32, .ptr, "test raw pointer ptr");
    conversion.checkSupported(?*anyopaque, .ptr, "test opaque pointer ptr");
    conversion.checkSupported(?*ExtensionNode, .ptr, "test extension pointer ptr");
    conversion.checkBoth(godot.builtins.Variant, "test Variant");
    conversion.checkBoth(Duration, "test Duration");
    conversion.checkBoth(Label, "test Label");
    conversion.checkBoth(NodeRef, "test NodeRef");
    conversion.checkBoth(ResourceRef, "test ResourceRef");
    conversion.checkBoth(?*ExtensionNode, "test extension pointer");

    if (comptime !std.mem.eql(u8, conversion.engineClassName(NodeRef), "Node")) {
        @compileError("NodeRef property class name must resolve through its engine type");
    }
}

fn analyzeVariantPrimitives(comptime T: type) void {
    var variant: godot.builtins.Variant = undefined;
    _ = conversion.decodeVariant(T, &variant);
    conversion.encodeVariant(T, @as(T, undefined), &variant);
}

fn analyzePtrPrimitives(comptime T: type) void {
    _ = conversion.decodePtr(T, null);
    conversion.encodePtr(T, undefined, null);
}

// Compile-only coverage; analyzed on every build.
fn analyzeCoverage() void {
    analyzeVariantPrimitives(i32);
    analyzeVariantPrimitives(godot.builtins.String);
    analyzeVariantPrimitives(godot.builtins.Variant);
    analyzeVariantPrimitives(*godot.classes.core.Node);
    analyzeVariantPrimitives(?*godot.classes.core.RefCounted);
    analyzeVariantPrimitives(Duration);
    analyzeVariantPrimitives(Label);
    analyzeVariantPrimitives(NodeRef);
    analyzeVariantPrimitives(ResourceRef);

    analyzePtrPrimitives(i32);
    analyzePtrPrimitives(godot.builtins.String);
    analyzePtrPrimitives(godot.builtins.Variant);
    analyzePtrPrimitives(*godot.classes.core.Node);
    analyzePtrPrimitives(?*godot.classes.core.RefCounted);
    analyzePtrPrimitives(*i32);
    analyzePtrPrimitives(?*anyopaque);
    analyzePtrPrimitives(*u8);
    analyzePtrPrimitives(?*ExtensionNode);
    analyzePtrPrimitives(Duration);
    analyzePtrPrimitives(Label);
    analyzePtrPrimitives(NodeRef);
    analyzePtrPrimitives(ResourceRef);
}

comptime {
    checkContract();
    _ = &analyzeCoverage;
    _ = &analyzePropertyBackend;
    _ = &analyzeVirtuals;
}

test "scalars and Duration round-trip through Variant and ptr slots" {
    var variant: godot.builtins.Variant = undefined;

    conversion.encodeVariant(i32, 7, &variant);
    try std.testing.expectEqual(interface.VariantType.int, variant.tag);
    try std.testing.expectEqual(@as(?i32, 7), conversion.decodeVariant(i32, &variant));

    conversion.encodeVariant(Duration, Duration{ .millis = 42 }, &variant);
    try std.testing.expectEqual(interface.VariantType.int, variant.tag);
    const duration = conversion.decodeVariant(Duration, &variant).?;
    try std.testing.expectEqual(@as(i32, 42), duration.millis);

    var slot: i64 = 0;
    conversion.encodePtr(i32, -3, @ptrCast(&slot));
    try std.testing.expectEqual(@as(i32, -3), conversion.decodePtr(i32, @ptrCast(&slot)));

    conversion.encodePtr(Duration, .{ .millis = 9 }, @ptrCast(&slot));
    try std.testing.expectEqual(@as(i32, 9), conversion.decodePtr(Duration, @ptrCast(&slot)).millis);
}

const std = @import("std");

const godot = @import("godot");
const Conversion = godot.annotations.Conversion;
const conversion = godot.conversion;
const interface = godot.bindings.interface;
