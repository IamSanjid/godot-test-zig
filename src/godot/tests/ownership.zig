//! Compile-only coverage for `godot.ownership`: `RefCounted` pointer shapes,
//! constructed-base release branches, and the null-optional no-op.
//!
//! The analysis functions contain engine calls; they are referenced at comptime
//! and never executed. Only the null-optional calls are safe to run.

/// Extension class used to analyze the engine-base resolution path.
const RefCountedExtension = struct {
    pub const Extends = classes.core.RefCounted;
    base: annotations.Base(Extends) = .{},
};

/// Non-class base for the direct-destroy branch shape.
const FakeBase = struct {};

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
    _ = godot.ownership.retainObjectReference(undefined);
}

/// Compile-only coverage; analyzed on every build.
fn analyzeConstructedBases() void {
    godot.ownership.releaseConstructedBase(classes.core.RefCounted, undefined);
    godot.ownership.releaseConstructedBase(classes.core.Node, undefined);
    godot.ownership.releaseConstructedBase(classes.core.Object, undefined);
    godot.ownership.releaseConstructedBase(FakeBase, undefined);
}

test "null optional retain and release are no-ops" {
    godot.ownership.retainRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.releaseRefCounted(?*const classes.core.RefCounted, null);
    godot.ownership.retainRefCounted(?*RefCountedExtension, null);
    godot.ownership.releaseRefCounted(?*const RefCountedExtension, null);
}

comptime {
    _ = &analyzeNullablePointers;
    _ = &analyzeOwnedPointers;
    _ = &analyzeObjectReferences;
    _ = &analyzeConstructedBases;
}

const godot = @import("godot");
const annotations = godot.annotations;
const classes = godot.classes;
