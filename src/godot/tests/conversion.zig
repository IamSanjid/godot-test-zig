//! Contract checks and compile-only coverage for `godot.internal.conversion`.
//!
//! Compile-only analysis instantiates every encode/decode/borrow/release
//! primitive; the runtime tests only touch scalar Variant and ptrcall slots and
//! the scalar-engine release probe, which need no engine initialization.

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

/// Converter whose engine representation is a managed builtin: `toEngine`
/// returns an owned `Array` handle, so a Variant view of it is not borrowable.
const Numbers = struct {
    count: i32,

    pub const GodotConversion = Conversion(.{
        .engine = godot.builtins.Array,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Numbers) godot.builtins.Array {
        _ = self;
        return godot.builtins.Array.init();
    }

    fn fromEngine(_: godot.builtins.Array) Numbers {
        return .{ .count = 0 };
    }
};

/// Probe converter whose declared type owns decoded storage: `deinit` must run
/// on both paths. The scalar engine type keeps the probe engine-free.
const ProbeOwned = struct {
    releases: *usize,

    pub const GodotConversion = Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: ProbeOwned) i32 {
        _ = self;
        return 0;
    }

    fn fromEngine(_: i32) ProbeOwned {
        return .{ .releases = &probe_release_count };
    }

    pub fn deinit(self: *ProbeOwned) void {
        self.releases.* += 1;
    }
};

/// Direct pointer target declaring `deinit`: a raw single-item pointer is a
/// direct ptrcall type, so releasing the decoded pointer must not reach it.
const ProbeDirect = struct {
    releases: *usize,

    pub fn deinit(self: *ProbeDirect) void {
        self.releases.* += 1;
    }
};

/// Incremented by the probe `deinit`s; each probe test resets it.
var probe_release_count: usize = 0;

/// Canonical scalar classifications for borrowed-Variant coverage.
const Mode = enum(i32) { idle, running = 3 };

const Flags = bitpack struct(u32) {
    first: bool = false,
    padding0: u31 = 0,
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

/// Compile-only virtual fixture with a `RefCounted` return: the generated
/// virtual signature is a raw borrowed pointer (`?*Class`), matching the
/// outgoing ABI, and arguments stay raw borrowed pointers.
const EffectFixture = struct {
    pub const Extends = godot.classes.core.AudioEffect;

    base: godot.annotations.Base(Extends) = .{},

    pub fn _instantiate(_: *@This()) ?*godot.classes.core.AudioEffectInstance {
        return null;
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
    // A RefCounted-returning override validates against the generated raw
    // borrowed-pointer virtual signature and analyzes the callback's
    // encode-only return path. Never executed.
    _ = comptime godot.registration.virtuals.collect(EffectFixture, EffectFixture.Extends);
}

/// Return type of a generated engine method.
fn engineMethodReturnType(comptime Method: anytype) type {
    return godot.reflect.FunctionReturnType(Method);
}

/// Return and parameter types of a generated virtual function-pointer type.
fn virtualFnReturnType(comptime FnPtr: type) type {
    return switch (@typeInfo(FnPtr)) {
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info.return_type orelse @compileError(
                "generated virtual must not return void here",
            ),
            else => @compileError("generated virtual metadata must be a function pointer"),
        },
        else => @compileError("generated virtual metadata must be a pointer type"),
    };
}

fn virtualFnParamType(comptime FnPtr: type, comptime index: usize) type {
    return switch (@typeInfo(FnPtr)) {
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => |info| info.param_types[index].?,
            else => @compileError("generated virtual metadata must be a function pointer"),
        },
        else => @compileError("generated virtual metadata must be a pointer type"),
    };
}

/// Compile-only return-shape contract: `RefCounted` engine-method results are
/// owning `ownership.Ref(Class)` values, virtual returns and other object
/// results stay raw borrowed pointers, and constructors return the class's typed
/// ownership handle; virtual arguments are unchanged.
fn checkGeneratedReturnShapes() void {
    if (comptime engineMethodReturnType(godot.classes.core.Resource.construct) !=
        godot.ownership.Ref(godot.classes.core.Resource))
    {
        @compileError("Resource.construct must return ownership.Ref(Resource)");
    }
    if (comptime engineMethodReturnType(godot.classes.core.Node.construct) !=
        godot.ownership.Owned(godot.classes.core.Node))
    {
        @compileError("Node.construct must return ownership.Owned(Node)");
    }
    if (comptime engineMethodReturnType(godot.classes.core.ResourceLoader.MemberFunctions.load) !=
        godot.ownership.Ref(godot.classes.core.Resource))
    {
        @compileError("ResourceLoader.load must return ownership.Ref(Resource)");
    }
    if (comptime engineMethodReturnType(godot.classes.core.Resource.MemberFunctions.duplicate) !=
        godot.ownership.Ref(godot.classes.core.Resource))
    {
        @compileError("Resource.duplicate must return ownership.Ref(Resource)");
    }
    if (comptime engineMethodReturnType(godot.classes.core.Node.MemberFunctions.getParent) !=
        ?*godot.classes.core.Node)
    {
        @compileError("Node.getParent must stay a raw borrowed ?*Node");
    }

    const Instantiate = godot.classes.core.AudioEffect.Virtual.Required._instantiate;
    if (comptime virtualFnReturnType(Instantiate) != ?*godot.classes.core.AudioEffectInstance) {
        @compileError("AudioEffect._instantiate virtual must stay a raw borrowed ?*AudioEffectInstance");
    }
    const Input = godot.classes.core.Node.Virtual.Optional._input;
    if (comptime virtualFnParamType(Input, 1) != *godot.classes.core.InputEvent) {
        @compileError("Node._input virtual arguments must stay raw borrowed pointers");
    }
}

fn expectSupport(comptime T: type, comptime variant: bool, comptime ptrcall: bool) void {
    const actual = comptime conversion.support(T);
    if (actual.variant != variant or actual.ptrcall != ptrcall) {
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

fn expectBorrowable(comptime T: type, comptime expected: bool) void {
    if (comptime conversion.canBorrowVariant(T) != expected) {
        @compileError("Unexpected Variant borrowability for " ++ @typeName(T));
    }
}

fn expectMethodArgument(comptime T: type, comptime expected: bool) void {
    if (comptime conversion.methodArgumentIsBorrowed(T) != expected) {
        @compileError("Unexpected method-argument borrowability for " ++ @typeName(T));
    }
}

fn expectCanBorrow(comptime T: type, comptime expected: bool) void {
    if (comptime godot.builtins.Variant.canBorrow(T) != expected) {
        @compileError("Unexpected Variant wrap capability for " ++ @typeName(T));
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
    expectSupport(godot.ownership.Owned(godot.classes.core.Node), false, false);

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
    conversion.checkSupported(i32, .ptrcall, "test scalar ptrcall");
    conversion.checkSupported(*i32, .ptrcall, "test raw pointer ptrcall");
    conversion.checkSupported(?*anyopaque, .ptrcall, "test opaque pointer ptrcall");
    conversion.checkSupported(?*ExtensionNode, .ptrcall, "test extension pointer ptrcall");
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

/// Borrowed-Variant classification: `borrowVariant` accepts only a direct type
/// with an inline or pointer Variant representation, or a converter whose engine
/// representation has no owned storage.
fn checkBorrowContract() void {
    @setEvalBranchQuota(1_000_000);

    // Direct borrowable types: canonical scalars, builtins, and object
    // pointers. A `RefCounted` pointer borrows too: the view pins no reference,
    // so the caller keeps its own alive for the call.
    expectBorrowable(i32, true);
    expectBorrowable(Mode, true);
    expectBorrowable(Flags, true);
    expectBorrowable(godot.builtins.Vector2, true);
    expectBorrowable(godot.builtins.String, true);
    expectBorrowable(godot.builtins.Array, true);
    expectBorrowable(godot.builtins.Dictionary, true);
    expectBorrowable(godot.builtins.Variant, true);
    expectBorrowable(*godot.classes.core.Node, true);
    expectBorrowable(?*godot.classes.core.Node, true);
    expectBorrowable(?*godot.classes.core.RefCounted, true);
    expectBorrowable(?*godot.classes.core.Resource, true);
    expectBorrowable(?*ExtensionNode, true);

    // Converters borrow without owned engine storage: scalar and object-engine
    // converters qualify (`Ref` included); a managed-builtin engine does not.
    expectBorrowable(Duration, true);
    expectBorrowable(NodeRef, true);
    expectBorrowable(ResourceRef, true);
    expectBorrowable(godot.ownership.Ref(godot.classes.core.Resource), true);
    expectBorrowable(Label, false);
    expectBorrowable(collections.Array(i32), false);
    expectBorrowable(Numbers, false);

    // Heap-backed builtins and packed arrays stay owned.
    expectBorrowable(godot.builtins.Transform3D, false);
    expectBorrowable(godot.builtins.AABB, false);
    expectBorrowable(godot.builtins.PackedByteArray, false);

    // `canBorrow` classifies the direct types the same way.
    expectCanBorrow(godot.builtins.Variant, true);
    expectCanBorrow(godot.builtins.String, true);
    expectCanBorrow(godot.builtins.Vector3, true);
    expectCanBorrow(?*godot.classes.core.Node, true);
    expectCanBorrow(godot.builtins.Transform3D, false);
    expectCanBorrow(godot.builtins.Basis, false);
    expectCanBorrow(godot.builtins.PackedByteArray, false);
    expectCanBorrow(*i32, false);
    expectCanBorrow(?*anyopaque, false);
}

/// Method-argument ownership gate: direct types are call-scoped borrowed, and a
/// converter qualifies only when its decoded value and engine representation own
/// nothing.
fn checkMethodArgumentContract() void {
    @setEvalBranchQuota(1_000_000);

    // Direct types: the adapter releases any Variant-path decode after the call.
    expectMethodArgument(i32, true);
    expectMethodArgument(godot.builtins.String, true);
    expectMethodArgument(godot.builtins.Array, true);
    expectMethodArgument(godot.builtins.PackedByteArray, true);
    expectMethodArgument(godot.builtins.Variant, true);
    expectMethodArgument(?*godot.classes.core.Node, true);
    expectMethodArgument(?*godot.classes.core.RefCounted, true);
    expectMethodArgument(*i32, true);
    expectMethodArgument(?*anyopaque, true);

    // Converters: scalar and non-`RefCounted` object representations are
    // borrowed; a declared `deinit` or owned engine storage is rejected.
    expectMethodArgument(Duration, true);
    expectMethodArgument(NodeRef, true);
    expectMethodArgument(ProbeOwned, false);
    expectMethodArgument(Label, false);
    expectMethodArgument(ResourceRef, false);
    expectMethodArgument(Numbers, false);
    expectMethodArgument(godot.ownership.Ref(godot.classes.core.Resource), false);
    expectMethodArgument(collections.Array(i32), false);
    expectMethodArgument(collections.Dictionary(godot.builtins.String, i32), false);

    // Valid types pass the contextual gate; the rejected shapes above are
    // compile errors and cannot be instantiated here.
    conversion.checkMethodArgument(i32, "test direct argument");
    conversion.checkMethodArgument(godot.builtins.String, "test managed builtin argument");
    conversion.checkMethodArgument(godot.builtins.Variant, "test Variant argument");
    conversion.checkMethodArgument(?*godot.classes.core.Node, "test object pointer argument");
    conversion.checkMethodArgument(Duration, "test scalar-converter argument");
    conversion.checkMethodArgument(NodeRef, "test object-converter argument");
}

fn analyzeVariantPrimitives(comptime T: type) void {
    var variant: godot.builtins.Variant = undefined;
    _ = conversion.decodeVariant(T, &variant);
    conversion.encodeVariant(T, @as(T, undefined), &variant);
}

/// Compile-only coverage of the borrowed-Variant primitive; signal emit
/// instantiates it for every borrowable argument type.
fn analyzeBorrowPrimitives(comptime T: type) void {
    var variant: godot.builtins.Variant = undefined;
    conversion.borrowVariant(T, @as(T, undefined), &variant);
}

fn analyzePtrcallPrimitives(comptime T: type) void {
    _ = conversion.decodePtrcallSlot(T, null);
    conversion.encodePtrcallSlot(T, undefined, null);
}

/// Typed collection wrappers convert through their marker's engine builtin;
/// analyzed on every build and never executed.
fn analyzeContainerPrimitives() void {
    analyzeVariantPrimitives(collections.Array(i32));
    analyzePtrcallPrimitives(collections.Array(i32));
    analyzeVariantPrimitives(collections.Dictionary(godot.builtins.String, i32));
    analyzePtrcallPrimitives(collections.Dictionary(godot.builtins.String, i32));
}

fn analyzeDeinitPrimitives(comptime T: type, comptime path: conversion.Path) void {
    var value: T = undefined;
    conversion.deinitDecodedArgument(T, path, &value);
}

/// Compile-only coverage of the decoded-argument release classification for
/// every representative declared type on both paths.
fn analyzeDeinitCoverage() void {
    analyzeDeinitPrimitives(i32, .variant);
    analyzeDeinitPrimitives(i32, .ptrcall);
    analyzeDeinitPrimitives(f64, .variant);
    analyzeDeinitPrimitives(f64, .ptrcall);
    analyzeDeinitPrimitives(Mode, .variant);
    analyzeDeinitPrimitives(Mode, .ptrcall);

    analyzeDeinitPrimitives(godot.builtins.Vector2, .variant);
    analyzeDeinitPrimitives(godot.builtins.Vector2, .ptrcall);
    analyzeDeinitPrimitives(godot.builtins.String, .variant);
    analyzeDeinitPrimitives(godot.builtins.String, .ptrcall);
    analyzeDeinitPrimitives(godot.builtins.Variant, .variant);
    analyzeDeinitPrimitives(godot.builtins.Variant, .ptrcall);

    analyzeDeinitPrimitives(*godot.classes.core.Node, .variant);
    analyzeDeinitPrimitives(*godot.classes.core.Node, .ptrcall);
    analyzeDeinitPrimitives(?*godot.classes.core.Node, .variant);
    analyzeDeinitPrimitives(?*godot.classes.core.Node, .ptrcall);
    analyzeDeinitPrimitives(?*godot.classes.core.RefCounted, .variant);
    analyzeDeinitPrimitives(?*godot.classes.core.RefCounted, .ptrcall);
    analyzeDeinitPrimitives(*i32, .ptrcall);
    analyzeDeinitPrimitives(?*anyopaque, .ptrcall);
    analyzeDeinitPrimitives(?*ExtensionNode, .variant);
    analyzeDeinitPrimitives(?*ExtensionNode, .ptrcall);

    analyzeDeinitPrimitives(Duration, .variant);
    analyzeDeinitPrimitives(Duration, .ptrcall);
    analyzeDeinitPrimitives(Label, .variant);
    analyzeDeinitPrimitives(Label, .ptrcall);
    analyzeDeinitPrimitives(NodeRef, .variant);
    analyzeDeinitPrimitives(NodeRef, .ptrcall);
    analyzeDeinitPrimitives(ResourceRef, .variant);
    analyzeDeinitPrimitives(ResourceRef, .ptrcall);
    analyzeDeinitPrimitives(ProbeOwned, .variant);
    analyzeDeinitPrimitives(ProbeOwned, .ptrcall);

    analyzeDeinitPrimitives(godot.ownership.Ref(godot.classes.core.Resource), .variant);
    analyzeDeinitPrimitives(godot.ownership.Ref(godot.classes.core.Resource), .ptrcall);
    analyzeDeinitPrimitives(collections.Array(i32), .variant);
    analyzeDeinitPrimitives(collections.Array(i32), .ptrcall);
    analyzeDeinitPrimitives(collections.Dictionary(godot.builtins.String, i32), .variant);
    analyzeDeinitPrimitives(collections.Dictionary(godot.builtins.String, i32), .ptrcall);
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

    analyzePtrcallPrimitives(i32);
    analyzePtrcallPrimitives(godot.builtins.String);
    analyzePtrcallPrimitives(godot.builtins.Variant);
    analyzePtrcallPrimitives(*godot.classes.core.Node);
    analyzePtrcallPrimitives(?*godot.classes.core.RefCounted);
    analyzePtrcallPrimitives(*i32);
    analyzePtrcallPrimitives(?*anyopaque);
    analyzePtrcallPrimitives(*u8);
    analyzePtrcallPrimitives(?*ExtensionNode);
    analyzePtrcallPrimitives(Duration);
    analyzePtrcallPrimitives(Label);
    analyzePtrcallPrimitives(NodeRef);
    analyzePtrcallPrimitives(ResourceRef);

    analyzeBorrowPrimitives(i32);
    analyzeBorrowPrimitives(Mode);
    analyzeBorrowPrimitives(Flags);
    analyzeBorrowPrimitives(godot.builtins.Vector2);
    analyzeBorrowPrimitives(godot.builtins.String);
    analyzeBorrowPrimitives(godot.builtins.Array);
    analyzeBorrowPrimitives(godot.builtins.Dictionary);
    analyzeBorrowPrimitives(godot.builtins.Variant);
    analyzeBorrowPrimitives(*godot.classes.core.Node);
    analyzeBorrowPrimitives(?*godot.classes.core.Node);
    analyzeBorrowPrimitives(?*ExtensionNode);
    analyzeBorrowPrimitives(Duration);
    analyzeBorrowPrimitives(NodeRef);

    analyzeContainerPrimitives();
}

comptime {
    checkContract();
    checkBorrowContract();
    checkMethodArgumentContract();
    checkGeneratedReturnShapes();
    _ = &analyzeCoverage;
    _ = &analyzeDeinitCoverage;
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
    conversion.encodePtrcallSlot(i32, -3, @ptrCast(&slot));
    try std.testing.expectEqual(@as(i32, -3), conversion.decodePtrcallSlot(i32, @ptrCast(&slot)));

    conversion.encodePtrcallSlot(Duration, .{ .millis = 9 }, @ptrCast(&slot));
    try std.testing.expectEqual(@as(i32, 9), conversion.decodePtrcallSlot(Duration, @ptrCast(&slot)).millis);
}

test "borrowVariant borrows scalar and nil Variant views" {
    // Borrowed views need no engine and must never be deinitialized.
    var borrowed: godot.builtins.Variant = undefined;

    conversion.borrowVariant(i32, 7, &borrowed);
    try std.testing.expectEqual(interface.VariantType.int, borrowed.tag);
    try std.testing.expectEqual(@as(?i32, 7), borrowed.as(i32));

    conversion.borrowVariant(Duration, Duration{ .millis = 42 }, &borrowed);
    try std.testing.expectEqual(interface.VariantType.int, borrowed.tag);
    try std.testing.expectEqual(@as(?i32, 42), borrowed.as(i32));

    conversion.borrowVariant(?*godot.classes.core.Node, null, &borrowed);
    try std.testing.expectEqual(interface.VariantType.nil, borrowed.tag);

    // A nullable value that is null becomes nil even for a non-optional
    // declared object type, matching `encodeVariant`.
    const no_node: ?*godot.classes.core.Node = null;
    conversion.borrowVariant(*godot.classes.core.Node, no_node, &borrowed);
    try std.testing.expectEqual(interface.VariantType.nil, borrowed.tag);
}

test "deinitDecodedArgument releases converter results on both paths" {
    probe_release_count = 0;

    var slot: i64 = 0;
    conversion.encodePtrcallSlot(i32, 0, @ptrCast(&slot));
    var ptrcall_value = conversion.decodePtrcallSlot(ProbeOwned, @ptrCast(&slot));
    try std.testing.expectEqual(@as(usize, 0), probe_release_count);
    conversion.deinitDecodedArgument(ProbeOwned, .ptrcall, &ptrcall_value);
    try std.testing.expectEqual(@as(usize, 1), probe_release_count);

    var variant: godot.builtins.Variant = undefined;
    conversion.encodeVariant(i32, 0, &variant);
    var variant_value = conversion.decodeVariant(ProbeOwned, &variant).?;
    try std.testing.expectEqual(@as(usize, 1), probe_release_count);
    conversion.deinitDecodedArgument(ProbeOwned, .variant, &variant_value);
    try std.testing.expectEqual(@as(usize, 2), probe_release_count);
}

test "deinitDecodedArgument ignores borrowed direct values" {
    probe_release_count = 0;

    var scalar: i32 = 7;
    conversion.deinitDecodedArgument(i32, .variant, &scalar);
    conversion.deinitDecodedArgument(i32, .ptrcall, &scalar);
    try std.testing.expect(scalar == 7);

    var plain: godot.builtins.Vector2 = .{ .x = 1, .y = 2 };
    conversion.deinitDecodedArgument(godot.builtins.Vector2, .variant, &plain);
    conversion.deinitDecodedArgument(godot.builtins.Vector2, .ptrcall, &plain);
    try std.testing.expect(plain.x == 1 and plain.y == 2);

    var node: ?*godot.classes.core.Node = null;
    conversion.deinitDecodedArgument(?*godot.classes.core.Node, .variant, &node);
    conversion.deinitDecodedArgument(?*godot.classes.core.Node, .ptrcall, &node);

    // The pointee declares `deinit`, but the decoded declared type is the raw
    // pointer: it is direct and borrowed, so release must not reach the object.
    var probe = ProbeDirect{ .releases = &probe_release_count };
    var probe_ptr: *ProbeDirect = &probe;
    conversion.deinitDecodedArgument(*ProbeDirect, .ptrcall, &probe_ptr);
    try std.testing.expectEqual(@as(usize, 0), probe_release_count);
}

const std = @import("std");

const godot = @import("godot");
const Conversion = godot.annotations.Conversion;
const collections = godot.collections;
const conversion = godot.internal.conversion;
const interface = godot.bindings.interface;
