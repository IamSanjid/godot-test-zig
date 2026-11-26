//! Compile-only coverage for `godot.ownership`: `RefCounted` pointer shapes,
//! the `Ref` and `Owned` ownership wrappers (layout, conversion, lifecycle,
//! fresh-object virtual returns), and the null-optional no-op.
//!
//! The analysis functions contain engine calls; they are referenced at comptime
//! and never executed. Only the null calls are safe to run.

/// Extension class used to analyze the engine-base resolution path.
const RefCountedExtension = struct {
    pub const Extends = classes.core.RefCounted;
    base: annotations.Base(Extends) = .{},
};

/// Extension class extending `Resource`: its handles reach `RefCounted` through
/// the `Base` marker chain.
const ResourceExtension = struct {
    pub const Extends = classes.core.Resource;
    base: annotations.Base(Extends) = .{},
};

/// Extension class extending a non-`RefCounted` engine class: the `Owned`
/// engine-base resolution path.
const NodeExtension = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
};

/// Compile-only coverage; analyzed on every build.
fn analyzeNullablePointers() void {
    godot.ownership.retainRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*RefCountedExtension, null);
    godot.ownership.releaseRefCounted(?*const RefCountedExtension, null);
}

/// Compile-only coverage; analyzed on every build.
fn analyzeOwnedPointers() void {
    godot.ownership.retainRefCounted(*classes.core.RefCounted, undefined);
    godot.ownership.releaseRefCounted(*const classes.core.RefCounted, undefined);
    godot.ownership.retainRefCounted(*RefCountedExtension, undefined);
    godot.ownership.releaseRefCounted(*const RefCountedExtension, undefined);
}

/// Compile-only coverage; analyzed on every build.
fn analyzeObjectReferences() void {
    _ = godot.ownership.retainObjectReference(@as(*classes.core.RefCounted, undefined));
}

/// Compile-only fresh-object virtual-return patterns; analyzed on every build.
/// The wrapper is local because `take` takes `*Self`, and moving it out leaves
/// the creation reference to the virtual return slot.
fn analyzeRefCountedVirtualReturn() ?*classes.core.Resource {
    var value = classes.core.Resource.construct();
    return value.take();
}

/// Compile-only fresh-object virtual-return patterns; analyzed on every build.
fn analyzeOwnedVirtualReturn() ?*classes.core.Node {
    var value = classes.core.Node.construct();
    return value.take();
}

/// Compile-only coverage of the `Ref` lifecycle; analyzed on every build.
fn analyzeRef(comptime Class: type) void {
    const ObjectRef = godot.ownership.Ref(Class);

    var owned = ObjectRef.init(undefined);
    _ = owned.get();
    _ = owned.isNull();
    var cloned = owned.clone();
    cloned.deinit();
    _ = owned.take();
    owned.deinit();
}

/// Compile-only coverage of the `Owned` lifecycle; analyzed on every build.
fn analyzeOwned(comptime Class: type) void {
    const ObjectOwned = godot.ownership.Owned(Class);

    var owned = ObjectOwned.empty;
    _ = owned.get();
    _ = owned.isNull();
    owned.deinit();

    var exclusive = ObjectOwned{ .ptr = undefined };
    _ = exclusive.take();
    exclusive.deinit();
}

/// `Ref` layout and declared conversion; a compile error means the owning value
/// stopped being a zero-cost object pointer or lost a conversion path.
fn checkRefContract(comptime Class: type) void {
    const ObjectRef = godot.ownership.Ref(Class);

    if (@sizeOf(ObjectRef) != @sizeOf(*anyopaque) or @alignOf(ObjectRef) != @alignOf(*anyopaque)) {
        @compileError("ownership.Ref must stay pointer-sized and pointer-aligned: " ++ @typeName(ObjectRef));
    }
    if (@sizeOf(ObjectRef) != @sizeOf(?*Class) or @alignOf(ObjectRef) != @alignOf(?*Class)) {
        @compileError("ownership.Ref must match its declared engine pointer type: " ++ @typeName(ObjectRef));
    }
    if (comptime ObjectRef.empty.ptr != null) {
        @compileError("ownership.Ref.empty must not own a reference");
    }

    const available = comptime godot.internal.conversion.support(ObjectRef);
    if (!available.variant or !available.ptrcall) {
        @compileError("ownership.Ref must convert on both paths: " ++ @typeName(ObjectRef));
    }
    const engine = comptime godot.internal.conversion.engineType(ObjectRef) orelse
        @compileError("ownership.Ref must declare an engine type: " ++ @typeName(ObjectRef));
    if (engine != ?*Class) @compileError("unexpected engine type for " ++ @typeName(ObjectRef));
    if (comptime godot.internal.conversion.variantType(ObjectRef) != .object) {
        @compileError("ownership.Ref must convert as an object Variant: " ++ @typeName(ObjectRef));
    }
    godot.internal.conversion.checkBoth(ObjectRef, "ownership.Ref");
}

/// `Owned` layout only; it is exclusive manual storage, never a declared
/// conversion type.
fn checkOwnedContract(comptime Class: type) void {
    const ObjectOwned = godot.ownership.Owned(Class);

    if (@sizeOf(ObjectOwned) != @sizeOf(*anyopaque) or @alignOf(ObjectOwned) != @alignOf(*anyopaque)) {
        @compileError("ownership.Owned must stay pointer-sized and pointer-aligned: " ++ @typeName(ObjectOwned));
    }
    if (@sizeOf(ObjectOwned) != @sizeOf(?*Class) or @alignOf(ObjectOwned) != @alignOf(?*Class)) {
        @compileError("ownership.Owned must match its declared engine pointer type: " ++ @typeName(ObjectOwned));
    }
    if (comptime ObjectOwned.empty.ptr != null) {
        @compileError("ownership.Owned.empty must not own an object");
    }

    const available = comptime godot.internal.conversion.support(ObjectOwned);
    if (available.variant or available.ptrcall) {
        @compileError("ownership.Owned must not be a conversion type: " ++ @typeName(ObjectOwned));
    }
    if (comptime godot.internal.conversion.engineType(ObjectOwned) != null) {
        @compileError("ownership.Owned must not declare an engine type: " ++ @typeName(ObjectOwned));
    }
}

fn checkRefContracts() void {
    checkRefContract(classes.core.RefCounted);
    checkRefContract(classes.core.Resource);
    checkRefContract(RefCountedExtension);
    checkRefContract(ResourceExtension);
}

fn checkOwnedContracts() void {
    checkOwnedContract(classes.core.Node);
    checkOwnedContract(classes.core.Object);
    checkOwnedContract(NodeExtension);
}

fn analyzeRefs() void {
    analyzeRef(classes.core.RefCounted);
    analyzeRef(classes.core.Resource);
    analyzeRef(RefCountedExtension);
    analyzeRef(ResourceExtension);
}

fn analyzeOwneds() void {
    analyzeOwned(classes.core.Node);
    analyzeOwned(classes.core.Object);
    analyzeOwned(NodeExtension);
}

test "null optional retain and release are no-ops" {
    godot.ownership.retainRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*RefCountedExtension, null);
    godot.ownership.releaseRefCounted(?*const RefCountedExtension, null);
}

test "null Ref owns nothing and stays empty" {
    const ResourceRef = godot.ownership.Ref(classes.core.Resource);

    var retained = ResourceRef.init(null);
    try std.testing.expect(retained.isNull());

    var empty = ResourceRef.empty;
    try std.testing.expect(empty.isNull());
    try std.testing.expect(empty.take() == null);

    retained.deinit();
    empty.deinit(); // The wrapper is already empty.
    try std.testing.expect(empty.isNull());
}

test "null Owned owns nothing and stays empty" {
    const NodeOwned = godot.ownership.Owned(classes.core.Node);

    var owned = NodeOwned.empty;
    try std.testing.expect(owned.isNull());
    try std.testing.expect(owned.take() == null);
    owned.deinit();
    try std.testing.expect(owned.isNull());
}

comptime {
    @setEvalBranchQuota(1_000_000);
    checkRefContracts();
    checkOwnedContracts();
    _ = &analyzeNullablePointers;
    _ = &analyzeOwnedPointers;
    _ = &analyzeObjectReferences;
    _ = &analyzeRefCountedVirtualReturn;
    _ = &analyzeOwnedVirtualReturn;
    _ = &analyzeRefs;
    _ = &analyzeOwneds;
}

const std = @import("std");

const godot = @import("godot");
const annotations = godot.annotations;
const classes = godot.classes;
