//! Engine object ownership: retain/release for `RefCounted` values and
//! destruction of a base constructed for an extension class. The lifetime
//! contract is documented in docs/ownership.md.

/// Takes a reference on a `RefCounted` pointer value; null optionals are a
/// no-op and non-`RefCounted` types are a compile error.
pub fn retainRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    _ = retainObjectReference(@ptrCast(object));
}

/// Takes an owning reference on an engine object already known to be
/// `RefCounted`. Returns false when the engine refuses the reference because
/// the object's reference count is zero.
pub fn retainObjectReference(object: *classes.core.Object) bool {
    return classes.core.RefCounted.reference(@ptrCast(object));
}

/// Releases a reference taken by `retainRefCounted`, destroying the object when
/// this was the last reference.
pub fn releaseRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    releaseRefCountedObject(object);
}

/// Releases a base constructed by `classdb_construct_object3` after a failed
/// creation. A `RefCounted` base owns one reference from construction;
/// `unreference` only decrements and reports whether the object must be
/// destroyed, so destroy it when that returns true. A non-`RefCounted` base is
/// destroyed directly.
pub fn releaseConstructedBase(comptime Base: type, base: *Base) void {
    if (comptime reflect.isRefCounted(Base)) {
        releaseRefCountedObject(@ptrCast(base));
    } else {
        destroyObject(base);
    }
}

/// Releases one reference and destroys the object when it was the last one.
fn releaseRefCountedObject(object: *classes.core.RefCounted) void {
    if (object.unreference()) destroyObject(object);
}

/// Destroys an engine object; the engine object ABI takes a single `Object*`.
fn destroyObject(object: anytype) void {
    classes.core.Object.destroy(@ptrCast(object));
}

/// Engine `RefCounted` object behind a pointer value, or null.
fn refCountedObject(comptime Value: type, value: Value) ?*classes.core.RefCounted {
    comptime if (!reflect.isRefCountedPointer(Value)) @compileError(
        "RefCounted ownership requires a RefCounted object pointer value type, found: " ++ @typeName(Value),
    );
    const target = comptime reflect.objectTarget(Value) orelse @compileError(
        "RefCounted ownership requires an object pointer value type, found: " ++ @typeName(Value),
    );
    const Class = target.class;
    const item: *const Class = if (comptime target.optional)
        @ptrCast(value orelse return null)
    else
        @ptrCast(value);
    return @ptrCast(reflect.engineBasePointer(Class, item));
}

const classes = @import("classes/classes.zig");
const reflect = @import("reflect/reflect.zig");
