//! Engine object ownership. `Ref(Class)` is the shared reference-counted owner
//! of a `RefCounted` object; `Owned(Class)` is the exclusive manual owner of a
//! non-`RefCounted` object the engine does not track. Raw object pointers and
//! the `Base` annotation stay borrowed. See docs/ownership.md.

/// Shared reference-counted ownership of a `RefCounted` class. One wrapper per
/// reference: copies alias the same reference, so use `clone` for another owner
/// and `take` to move the reference out.
pub fn Ref(comptime Class: type) type {
    if (comptime !isRefCountedClass(Class)) @compileError(
        "Ref requires an engine or extension class type inheriting RefCounted, found: " ++ @typeName(Class),
    );

    return struct {
        /// The owned object pointer; release it through `deinit`.
        ptr: ?*Class,

        const Self = @This();

        /// An empty wrapper, owning no reference.
        pub const empty: Self = .{ .ptr = null };

        /// Declared conversion: object pointers are borrowed in both directions.
        pub const GodotConversion = conversion_marker.Conversion(.{
            .engine = ?*Class,
            .to_engine = toEngine,
            .from_engine = fromEngine,
        });

        /// Takes an owning reference on `value`; null is a no-op. Returns an
        /// empty `Ref` when the engine refuses (the object is already at refcount
        /// zero and being destroyed).
        pub fn init(value: ?*Class) Self {
            const object = refCountedObject(?*Class, value) orelse return empty;
            if (!retainObjectReference(object)) return empty;
            return .{ .ptr = value };
        }

        /// Returns another owning wrapper by taking a new reference on the same
        /// object. Use this instead of copying a wrapper you keep.
        pub fn clone(self: Self) Self {
            return init(self.ptr);
        }

        /// Returns the borrowed object pointer; the caller does not own it.
        pub fn get(self: Self) ?*Class {
            return self.ptr;
        }

        /// Moves the owned reference out and empties the wrapper; the caller
        /// becomes its owner.
        pub fn take(self: *Self) ?*Class {
            const object = self.ptr;
            self.ptr = null;
            return object;
        }

        /// Releases the owned reference, destroying the object when it was the
        /// last one; the wrapper is empty afterwards.
        pub fn deinit(self: *Self) void {
            releaseRefCounted(?*Class, self.ptr);
            self.ptr = null;
        }

        pub fn isNull(self: Self) bool {
            return self.ptr == null;
        }

        /// Conversion adapter: the marker passes the declared value by value.
        fn toEngine(self: Self) ?*Class {
            return self.ptr;
        }

        /// Conversion adapter: decoded object pointers are borrowed, so the
        /// wrapper retains its own reference.
        fn fromEngine(value: ?*Class) Self {
            return init(value);
        }

        comptime {
            checkPointerLayout("ownership.Ref", Self, Class);
        }
    };
}

/// Exclusive manual ownership of an engine or extension class that does not
/// inherit `RefCounted`. The engine does not track these objects, so `deinit`
/// destroys the owned object; only own objects not handed to the scene tree or
/// the engine, and use `take` to hand one over.
pub fn Owned(comptime Class: type) type {
    if (comptime !reflect.isClassType(Class)) @compileError(
        "Owned requires an engine or extension class type, found: " ++ @typeName(Class),
    );
    if (comptime isRefCountedClass(Class)) @compileError(
        "Owned requires a class that does not inherit RefCounted; use Ref for: " ++ @typeName(Class),
    );

    return struct {
        /// The owned object pointer; destroy it through `deinit`.
        ptr: ?*Class,

        const Self = @This();

        /// An empty wrapper, owning no object.
        pub const empty: Self = .{ .ptr = null };

        /// Returns the borrowed object pointer; the caller does not own it.
        pub fn get(self: Self) ?*Class {
            return self.ptr;
        }

        /// Moves the owned object pointer out and empties the wrapper; the
        /// caller becomes responsible for destroying the object.
        pub fn take(self: *Self) ?*Class {
            const object = self.ptr;
            self.ptr = null;
            return object;
        }

        /// Destroys the owned object through `Object.destroy` and empties the
        /// wrapper.
        pub fn deinit(self: *Self) void {
            if (self.ptr) |object| {
                destroyObject(reflect.engineBasePointer(Class, object));
            }
            self.ptr = null;
        }

        pub fn isNull(self: Self) bool {
            return self.ptr == null;
        }

        comptime {
            checkPointerLayout("ownership.Owned", Self, Class);
        }
    };
}

/// Takes a reference on a `RefCounted` pointer value; null optionals are a
/// no-op and non-`RefCounted` types are a compile error.
pub fn retainRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    _ = retainObjectReference(object);
}

/// Takes an owning reference on an engine object already known to be
/// `RefCounted`. Returns false when the engine refuses the reference because
/// the object's reference count is zero.
pub fn retainObjectReference(object: *classes.core.RefCounted) bool {
    return object.reference();
}

/// Releases a reference taken by `retainRefCounted`, destroying the object when
/// this was the last reference.
pub fn releaseRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    releaseRefCountedObject(object);
}

/// True for engine or extension class types inheriting `RefCounted`.
fn isRefCountedClass(comptime Class: type) bool {
    return reflect.isClassType(Class) and reflect.inheritsFrom(Class, classes.core.RefCounted);
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

/// Compile-time layout invariant for owning handles.
fn checkPointerLayout(comptime name: []const u8, comptime Self: type, comptime Class: type) void {
    if (@sizeOf(Self) != @sizeOf(?*Class) or @alignOf(Self) != @alignOf(?*Class)) {
        @compileError(name ++ " must stay pointer-sized and pointer-aligned");
    }
}

const conversion_marker = @import("annotations/conversion.zig");
const classes = @import("classes/classes.zig");
const reflect = @import("reflect/reflect.zig");
