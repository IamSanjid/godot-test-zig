//! Hand-written `Variant`: borrowed views, owning construction, typed extraction.
//!
//! A Godot `Variant` is a tagged `extern` union: 24 bytes in the single-precision
//! builtin layout, 40 bytes in the double-precision one. This file only touches
//! the tag directly and only writes the `Data` union for values whose engine
//! representation is the value itself (tag, scalar and plain value builtins).
//! Every non-trivial conversion goes through the engine procedures
//! `get_variant_from_type_constructor`, `get_variant_to_type_constructor`,
//! `variant_new_copy` and `variant_destroy`.
//!
//! # Ownership
//!
//! - `wrap` is **borrowed**: pointer-backed payloads alias the caller's value and
//!   inline value types are copied; no engine allocation or reference-count
//!   change happens. A wrapped Variant must never be `deinit`ed; take an owning
//!   copy with `clone` when one is needed.
//! - `init` is **owned**: non-trivial builtins are copied by the engine into
//!   fresh Variant storage (reference-counted builtins get their own reference),
//!   and the argument stays owned by the caller. Object pointers store the
//!   engine pointer plus instance id; `RefCounted` objects get exactly one
//!   owning reference added with the object's `reference()`. Release the Variant
//!   with `deinit`.
//! - `clone` creates an owning copy (`variant_new_copy`); Variant copies are
//!   shallow, so reference types share their engine storage but the copy owns
//!   its own references.
//! - `as` returns extracted values: scalars and plain value builtins are plain
//!   copies; types with a `deinit` declaration (String, StringName, NodePath,
//!   Callable, Signal, Array, Dictionary and packed arrays) come back owned and
//!   must be deinitialized by the caller; object pointers are borrowed from the
//!   Variant.
//!
//! # Extension classes
//!
//! Zig extension classes (normal structs with an `Extends` alias) are supported
//! for a safe subset of object conversion. A Variant object can only hold an
//! engine object, so `wrap`/`init` resolve an extension instance to its ultimate
//! engine base object. That walk requires a `Base(<direct parent>)` marker field
//! on every extension level; a missing marker is a compile error. `as` goes the
//! other way: it borrows the engine base object from the Variant and returns the
//! registered Zig instance through the base's `asInstance(Extension)` binding
//! (or `null` when no binding exists).
//!
//! Godot 4 does not implement registering an extension class that inherits
//! another extension class (`gdextension.cpp`: "Unimplemented yet"), so at
//! runtime the supported shape is a direct extension class over an engine class.
//! The conversion helpers traverse a manually built extension -> extension chain,
//! but registering such a chain is outside the current runtime support.
//!
//! `as` never performs an implicit Variant conversion: it returns `null` unless
//! the Variant tag is exactly the tag of the requested type. Use the engine
//! conversion functions if a converting read is required.

pub const Variant = extern struct {
    pub const GodotClassName = "Variant";

    tag: interface.VariantType align(@alignOf(bindings.builtins.Variant)),
    data: Data align(@alignOf(bindings.builtins.Variant)),

    /// Opaque engine-private packed-array header.
    ///
    /// The engine stores a refcounted header (with engine-owned layout details)
    /// behind `Data.packed_*`. This type only gives the pointer a distinct typed
    /// name instead of `?*anyopaque`; hand-written code never constructs,
    /// mutates, dereferences or relies on the header layout. Packed arrays only
    /// move through the engine Variant constructors/destructors.
    fn PackedArrayRef(comptime T: type) type {
        _ = T;
        return opaque {};
    }

    const Data = extern union {
        aabb: *AABB,
        array: *Array,
        basis: *Basis,
        bool: bool,
        callable: Callable,
        color: Color,
        dictionary: *Dictionary,
        // Engine layout fact: `Variant::_data._float` is C++ `double` in every
        // build configuration. This is not derived from `abi.Box`; `Box` only
        // describes ptrcall scalar slots. The Variant's 24/40-byte size comes
        // from its `_mem[sizeof(real_t) * 4]` / generated builtin member sizes,
        // not from this field.
        float: f64,
        int: i64,
        nil: void,
        node_path: NodePath,
        object: extern struct {
            obj_id: native.ObjectID,
            object: *Object,
        },
        packed_byte_array: *PackedArrayRef(builtins.PackedByteArray),
        packed_color_array: *PackedArrayRef(builtins.PackedColorArray),
        packed_float32_array: *PackedArrayRef(builtins.PackedFloat32Array),
        packed_float64_array: *PackedArrayRef(builtins.PackedFloat64Array),
        packed_int32_array: *PackedArrayRef(builtins.PackedInt32Array),
        packed_int64_array: *PackedArrayRef(builtins.PackedInt64Array),
        packed_string_array: *PackedArrayRef(builtins.PackedStringArray),
        packed_vector2_array: *PackedArrayRef(builtins.PackedVector2Array),
        packed_vector3_array: *PackedArrayRef(builtins.PackedVector3Array),
        packed_vector4_array: *PackedArrayRef(builtins.PackedVector4Array),
        plane: Plane,
        projection: *Projection,
        quaternion: Quaternion,
        rect2: Rect2,
        rect2i: Rect2i,
        rid: RID,
        signal: Signal,
        string: String,
        string_name: StringName,
        transform2d: *Transform2D,
        transform3d: *Transform3D,
        vector2: Vector2,
        vector2i: Vector2i,
        vector3: Vector3,
        vector3i: Vector3i,
        vector4: Vector4,
        vector4i: Vector4i,
        // max = 38,
    };

    pub fn toBinding(self: *const Variant) bindings.builtins.Variant {
        return @as(*const bindings.builtins.Variant, @ptrCast(self)).*;
    }

    pub fn fromBinding(v: anytype) Variant {
        const T = @TypeOf(v);
        return switch (T) {
            *bindings.builtins.Variant => @as(*Variant, @ptrCast(v)).*,
            *const bindings.builtins.Variant => @as(*const Variant, @ptrCast(v)).*,
            bindings.builtins.Variant => @as(*const Variant, @ptrCast(&v)).*,
            else => @compileError("Expected bindings.builtins.Variant by value or a pointer to it, found: " ++ @typeName(T)),
        };
    }

    /// The Variant type used to store `T`, or `null` when `T` has none.
    ///
    /// Scalars map to `bool`/`int`/`float` in canonical storage order; every
    /// codegen builtin type in `builtins.zig` maps to its GDExtension
    /// `VariantType`; engine object class pointers and Zig extension class
    /// pointers (`*C`/`?*C`) map to `object`. `Variant` itself returns `null`
    /// because GDExtension has no Variant VariantType: a Variant is stored
    /// transparently in other Variants.
    ///
    /// This maps storage only: per-class object metadata (class name, properties)
    /// belongs to the future property layer and is not built here.
    pub fn typeFor(comptime T: type) ?interface.VariantType {
        if (comptime T == Variant) return null;
        if (comptime abi.Box(T).canonical) return scalarVariantType(T);
        if (comptime builtinVariantType(T)) |variant_type| return variant_type;
        if (comptime reflect.objectTarget(T) != null) return .object;
        return null;
    }

    /// Creates a **borrowed** Variant view of `value`.
    ///
    /// `T` is the value type; `value` must be `*T`, `*const T`, `?*T` or
    /// `?*const T`. A `null` optional pointer produces `Variant.nil`.
    ///
    /// No engine allocation happens and no reference counts change. Pointer-
    /// backed and engine-managed builtins borrow the source payload; scalars and
    /// plain value builtins copy their bytes into the Variant payload. The
    /// result is valid only while the pointed value is alive and must never be
    /// passed to `deinit`; use `clone` when an owning Variant is needed.
    ///
    /// Deliberate limits:
    /// - packed arrays compile-error (their Variant storage is an engine-owned
    ///   copy-on-write ref; use `init`),
    /// - builtins the engine keeps behind an owned heap allocation (AABB, Basis,
    ///   Projection, Transform2D, Transform3D) compile-error as well; `init`
    ///   copies them into owned Variant storage,
    /// - object pointers are borrowed: for `RefCounted` the Variant does not hold
    ///   a reference, so the pointed object must outlive the borrowed Variant.
    ///   The stored instance ID still carries the engine's ref-counted marker, so
    ///   if the engine copies the wrapped Variant it takes its own reference.
    ///
    /// Object class pointers:
    /// - engine class pointer: stores the engine object pointer plus instance id
    ///   (the behavior above),
    /// - extension class pointer (`*Extension`): resolves the ultimate engine base
    ///   object through the `Base` marker chain and borrows *that engine object*;
    ///   the Zig extension instance itself is not stored in the Variant. The
    ///   extension instance and its engine base must outlive the wrapped Variant.
    ///   A missing `Base` marker is a compile error.
    ///
    /// `wrap(Variant, &v)` returns a borrowed alias of `v` (Variant has no
    /// VariantType of its own); the alias has the same lifetime and no-`deinit`
    /// contract as every other wrapped value.
    pub fn wrap(comptime T: type, value: anytype) Variant {
        const VT = @TypeOf(value);
        if (VT != *const T and VT != *T and VT != ?*T and VT != ?*const T) {
            @compileError(std.fmt.comptimePrint(
                "Variant.wrap expects a pointer to {s} (or an optional pointer), found: {s}",
                .{ @typeName(T), @typeName(VT) },
            ));
        }

        if (comptime isPackedArray(T)) {
            @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
                ": packed arrays are copy-on-write engine values. Use Variant.init for an owned Variant.");
        }
        if (comptime isHeapBuiltin(T)) {
            @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
                ": the engine keeps it behind an owned heap allocation. Use Variant.init for an owned Variant.");
        }

        const pointer: *const T = if (comptime VT == ?*T or VT == ?*const T)
            (value orelse return Variant.nil)
        else
            value;

        if (comptime abi.Box(T).canonical) {
            return wrapScalar(T, pointer.*);
        } else if (comptime T == Variant) {
            return pointer.*;
        } else if (comptime builtinVariantType(T)) |variant_type| {
            return wrapBuiltin(T, variant_type, pointer.*);
        } else if (comptime reflect.isEngineObjectClass(T)) {
            return wrapEngineObject(T, pointer);
        } else if (comptime reflect.isExtensionClass(T)) {
            return wrapExtensionObject(T, pointer);
        } else {
            unsupportedWrap(T);
        }
    }

    /// Creates an **owning** Variant from `value`.
    ///
    /// Scalar values are stored directly. Non-trivial builtins are copied into
    /// fresh engine Variant storage through `get_variant_from_type_constructor`,
    /// including packed arrays (the engine creates the copy-on-write ref, this
    /// layer never touches it). `value` remains owned by the caller.
    ///
    /// For object classes `T` is a pointer (`*C`, `*const C`, `?*C` or
    /// `?*const C`); a `null` optional pointer produces `Variant.nil`. The object data
    /// is constructed explicitly instead of going through Godot's
    /// `Variant(const Object*)` constructor, whose `RefCounted::init_ref()` has
    /// creation-reference accounting that can consume an unclaimed creation
    /// reference instead of adding one:
    /// - non-`RefCounted` objects are stored as the engine pointer plus instance
    ///   id without a reference; the engine owns object lifetime and the object
    ///   must outlive the Variant's use,
    /// - `RefCounted` objects get exactly one owning reference through the
    ///   object's `reference()`, and the Variant cleanup/`deinit` releases it.
    ///   The caller's own reference is unaffected. If the engine reports the
    ///   object as no longer referenceable (refcount 0), `Variant.nil` is returned.
    ///
    /// RefCounted-ness is decided from the runtime engine instance ID (its
    /// ref-counted bit is the same flag Godot's Variant object cleanup uses), so
    /// an upcast `*Object` that actually points at a `RefCounted` is handled
    /// correctly.
    ///
    /// Extension class pointers (`*Extension`, `?*Extension`, const variants) are
    /// resolved through the `Base` marker chain to the ultimate engine base
    /// object, and that engine object is stored with the ownership rules above.
    /// The Zig extension instance itself is not stored in the Variant. Every
    /// extension level must declare `annotations.Base(<direct parent>)`; a missing
    /// marker is a clear compile error. Note that registering an extension class
    /// that inherits another extension class is not implemented by Godot 4, so
    /// in practice this is used for a direct extension class over an engine class
    /// (the conversion helpers still traverse a manually built chain).
    pub fn init(comptime T: type, value: T) Variant {
        if (comptime abi.Box(T).canonical) {
            return wrapScalar(T, value);
        } else if (comptime T == Variant) {
            return value.clone();
        } else if (comptime builtinVariantType(T)) |variant_type| {
            return initBuiltin(T, variant_type, value);
        } else if (comptime reflect.objectTarget(T)) |target| {
            return initObjectPointer(target, value);
        } else {
            unsupportedInit(T);
        }
    }

    /// Extracts `T` from the Variant when its tag is exactly the tag of `T`.
    ///
    /// Returns `null` for a tag mismatch; no implicit Variant conversion is
    /// performed. Integer, enum and bitfield targets also return `null` when the
    /// Variant `i64` payload does not fit the requested type; exhaustive enums
    /// also reject values that are not declared members. Unsigned 64-bit
    /// targets are bit-preserving. Ownership follows the extracted type:
    /// - scalars and plain value builtins (vectors, rects, transforms, RID,
    ///   Color, ...) are returned by value,
    /// - `String`, `StringName`, `NodePath`, `Callable`, `Signal`, `Array`,
    ///   `Dictionary` and packed arrays are returned **owned** (they have a
    ///   `deinit` declaration); deinitialize them with `deinit`,
    /// - object pointers (`*C`) are borrowed from the Variant (the Variant keeps
    ///   the owning reference it holds for `RefCounted` objects; take your own
    ///   reference before retaining one). The object tag is checked, but the
    ///   runtime class and object lifetime are not: the Variant must hold a live
    ///   object of the requested class,
    /// - extension class pointers (`*Extension`) resolve the engine base object
    ///   stored in the Variant and return the registered Zig instance through
    ///   that base's `asInstance(Extension)`. The result is borrowed (owned by the
    ///   engine object binding) and is `null` when the Variant holds a plain
    ///   engine object or an object without a binding for that exact extension
    ///   class. A missing `Base` marker is a compile error.
    /// - `Variant` itself returns an owned `clone` and never `null`.
    pub fn as(self: *const Variant, comptime T: type) ?T {
        if (comptime abi.Box(T).canonical) {
            if (self.tag != scalarVariantType(T)) return null;
            return scalarFromData(T, self.data);
        } else if (comptime T == Variant) {
            return self.clone();
        } else if (comptime builtinVariantType(T)) |variant_type| {
            if (self.tag != variant_type) return null;
            return asBuiltin(T, variant_type, self);
        } else if (comptime reflect.objectTarget(T)) |target| {
            return asObjectPointer(T, target, self);
        } else {
            unsupportedAs(T);
        }
    }

    /// Creates an owning copy of the Variant (`variant_new_copy`).
    ///
    /// The copy is shallow in Variant terms: reference types share their engine
    /// storage, but the new Variant owns its own references and must be
    /// deinitialized. This is also how a borrowed `wrap` view becomes owning.
    pub fn clone(self: *const Variant) Variant {
        var result: Variant = undefined;
        runtime.dispatch(.variant_new_copy, .{
            @as(interface.UninitializedVariantPtr, @ptrCast(&result)),
            @as(interface.ConstVariantPtr, @ptrCast(self)),
        });
        return result;
    }

    /// Destroys an owning Variant and leaves the payload as `nil`.
    ///
    /// Only call this for Variants this layer owns: results of `init`, `clone`,
    /// or a Variant moved out of an engine binding. Never call it on a Variant
    /// produced by `wrap` or on a borrowed Variant argument. For object variants
    /// this is where the Variant's owning `RefCounted` reference (if any) is
    /// released, matching Godot's own Variant cleanup.
    pub fn deinit(self: *Variant) void {
        runtime.dispatch(.variant_destroy, .{@as(interface.VariantPtr, @ptrCast(self))});
        self.* = nil;
    }

    /// Precomputed nil Variant value. Copy it when an owning Variant is needed;
    /// it contains no engine-managed references.
    pub const nil: Variant = .{ .tag = .nil, .data = .{ .nil = {} } };
};

comptime {
    bindings.builtins.variant.checkTypeLayout(Variant);
}

comptime {
    // The type mapping is part of the public contract: every codegen builtin type
    // must have exactly its GDExtension VariantType, scalars must map to the
    // canonical scalar tags, object class pointers must map to `object`, and
    // `Variant` itself must stay transparent (no VariantType).
    for (builtin_mappings) |mapping| {
        if (Variant.typeFor(mapping.Type) != mapping.variant_type) {
            @compileError("Variant.typeFor is missing or mis-maps builtin: " ++ @typeName(mapping.Type));
        }
    }

    for (.{ i8, u8, i16, u16, i32, u32, i64, u64 }) |T| {
        if (Variant.typeFor(T) != .int) @compileError("Variant.typeFor must map integer type to .int: " ++ @typeName(T));
    }
    for (.{ f32, f64 }) |T| {
        if (Variant.typeFor(T) != .float) @compileError("Variant.typeFor must map float type to .float: " ++ @typeName(T));
    }
    if (Variant.typeFor(bool) != .bool) @compileError("Variant.typeFor must map bool to .bool");

    if (Variant.typeFor(Variant) != null) @compileError("Variant.typeFor(Variant) must be null (transparent storage)");

    if (Variant.typeFor(*Object) != .object or Variant.typeFor(?*Object) != .object) {
        @compileError("Variant.typeFor must map object class pointers to .object");
    }
    if (Variant.typeFor(*classes.core.RefCounted) != .object or Variant.typeFor(*classes.core.Node) != .object) {
        @compileError("Variant.typeFor must map engine class pointers to .object");
    }

    {
        const Mode = enum(u32) { a = 0, b = 1 };
        const Flags = bitpack struct(u32) {
            first: bool = false,
            _pad0: u31 = 0,
        };
        if (Variant.typeFor(Mode) != .int) @compileError("Variant.typeFor must map enums to .int");
        if (Variant.typeFor(Flags) != .int) @compileError("Variant.typeFor must map readable bitfields to .int");
    }
}

comptime {
    // Compile-only coverage for object pointer conversion: engine classes, a
    // direct Zig extension class over an engine class, and an
    // extension -> extension chain. The fake Base marker mirrors
    // `annotations.Base` structurally; `reflect.base` recognizes markers without
    // the annotation layer, so this block keeps Variant's object conversion
    // instantiated and type-checked on every build.
    const Coverage = struct {
        fn FakeBase(comptime B: type) type {
            return struct {
                pub const BaseFor = B;

                _ptr: *B = undefined,

                pub fn get(self: *const @This()) *B {
                    return self._ptr;
                }

                pub fn set(self: *@This(), value: *B) void {
                    self._ptr = value;
                }
            };
        }

        /// Direct extension class over an engine class.
        const DirectExtension = struct {
            pub const Extends = classes.core.Node;
            base: FakeBase(Extends) = .{},
        };

        /// Extension class whose `Extends` is another extension class.
        const ChainedExtension = struct {
            pub const Extends = DirectExtension;
            base: FakeBase(Extends) = .{},
        };

        fn check() void {
            var variant: Variant = undefined;

            // Engine class pointers: existing behavior.
            _ = Variant.wrap(classes.core.Object, @as(*const classes.core.Object, undefined));
            _ = Variant.wrap(classes.core.Node, @as(?*const classes.core.Node, null));
            _ = Variant.init(*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.init(?*classes.core.RefCounted, null);
            _ = variant.as(*classes.core.Object);
            _ = variant.as(*const classes.core.Node);

            // Direct extension class.
            _ = Variant.wrap(DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.wrap(DirectExtension, @as(?*DirectExtension, null));
            _ = Variant.init(*DirectExtension, @as(*DirectExtension, undefined));
            _ = Variant.init(*const DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.init(?*const DirectExtension, null);
            _ = Variant.init(?*DirectExtension, @as(?*DirectExtension, null));
            _ = variant.as(*DirectExtension);
            _ = variant.as(*const DirectExtension);

            // Extension -> extension chain.
            _ = Variant.wrap(ChainedExtension, @as(*const ChainedExtension, undefined));
            _ = Variant.init(*ChainedExtension, @as(*ChainedExtension, undefined));
            _ = Variant.init(*const ChainedExtension, @as(*const ChainedExtension, undefined));
            _ = variant.as(*ChainedExtension);

            if (comptime reflect.isExtensionClass(DirectExtension) == false) {
                @compileError("Variant.wrap/init extension conversion: direct extension class was not recognized");
            }
            if (comptime Variant.typeFor(*DirectExtension) == null) {
                @compileError("Variant.typeFor must map direct extension class pointers to .object");
            }
            if (comptime Variant.typeFor(?*ChainedExtension) == null) {
                @compileError("Variant.typeFor must map chained extension class pointers to .object");
            }
        }

        // The raw bindgen `Variant.wrap` has a separate generic object branch.
        // Instantiate it here with concrete binding classes so the binding
        // layer's class-pointer cast cannot regress lazily.
        fn rawWrapEngine(dispatcher: *const runtime.DefaultDispatcher, node: *bindings.classes.core.Node) void {
            _ = bindings.builtins.Variant.wrap(dispatcher, bindings.classes.core.Node, node);
        }

        fn rawWrapOptional(dispatcher: *const runtime.DefaultDispatcher, node: ?*bindings.classes.core.Node) void {
            _ = bindings.builtins.Variant.wrap(dispatcher, bindings.classes.core.Node, node);
        }

        fn rawWrapRefCounted(dispatcher: *const runtime.DefaultDispatcher, resource: *bindings.classes.core.RefCounted) void {
            _ = bindings.builtins.Variant.wrap(dispatcher, bindings.classes.core.RefCounted, resource);
        }

        fn scalarCoverage(variant: *const Variant) void {
            const Mode = enum(u32) { a = 0, b = 1 };
            const Flags = bitpack struct(u32) {
                first: bool = false,
                _pad0: u31 = 0,
            };
            _ = variant.as(Mode);
            _ = variant.as(Flags);
            _ = variant.as(usize);
            _ = variant.as(i8);
            _ = variant.as(u8);
        }

        // Exercise every mapped builtin's engine constructor bridges without
        // executing any engine call. Layout compatibility is owned by the
        // generated checkTypeLayout blocks and builtins.zig's layoutCheck.
        fn builtinCoverage(variant: *const Variant) void {
            inline for (builtin_mappings) |mapping| {
                _ = Variant.init(mapping.Type, undefined);
                _ = variant.as(mapping.Type);
            }
        }
    };
    _ = &Coverage.check;
    _ = &Coverage.rawWrapEngine;
    _ = &Coverage.rawWrapOptional;
    _ = &Coverage.rawWrapRefCounted;
    _ = &Coverage.scalarCoverage;
    _ = &Coverage.builtinCoverage;
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

/// A builtin type and the GDExtension Variant type it occupies.
const BuiltinMapping = struct {
    Type: type,
    variant_type: interface.VariantType,
};

/// Every codegen builtin type in `builtins.zig`, mapped to its Variant type.
const builtin_mappings = [_]BuiltinMapping{
    .{ .Type = builtins.String, .variant_type = .string },
    .{ .Type = builtins.Vector2, .variant_type = .vector2 },
    .{ .Type = builtins.Vector2i, .variant_type = .vector2i },
    .{ .Type = builtins.Rect2, .variant_type = .rect2 },
    .{ .Type = builtins.Rect2i, .variant_type = .rect2i },
    .{ .Type = builtins.Vector3, .variant_type = .vector3 },
    .{ .Type = builtins.Vector3i, .variant_type = .vector3i },
    .{ .Type = builtins.Transform2D, .variant_type = .transform2d },
    .{ .Type = builtins.Vector4, .variant_type = .vector4 },
    .{ .Type = builtins.Vector4i, .variant_type = .vector4i },
    .{ .Type = builtins.Plane, .variant_type = .plane },
    .{ .Type = builtins.Quaternion, .variant_type = .quaternion },
    .{ .Type = builtins.AABB, .variant_type = .aabb },
    .{ .Type = builtins.Basis, .variant_type = .basis },
    .{ .Type = builtins.Transform3D, .variant_type = .transform3d },
    .{ .Type = builtins.Projection, .variant_type = .projection },
    .{ .Type = builtins.Color, .variant_type = .color },
    .{ .Type = builtins.StringName, .variant_type = .string_name },
    .{ .Type = builtins.NodePath, .variant_type = .node_path },
    .{ .Type = builtins.RID, .variant_type = .rid },
    .{ .Type = builtins.Callable, .variant_type = .callable },
    .{ .Type = builtins.Signal, .variant_type = .signal },
    .{ .Type = builtins.Dictionary, .variant_type = .dictionary },
    .{ .Type = builtins.Array, .variant_type = .array },
    .{ .Type = builtins.PackedByteArray, .variant_type = .packed_byte_array },
    .{ .Type = builtins.PackedInt32Array, .variant_type = .packed_int32_array },
    .{ .Type = builtins.PackedInt64Array, .variant_type = .packed_int64_array },
    .{ .Type = builtins.PackedFloat32Array, .variant_type = .packed_float32_array },
    .{ .Type = builtins.PackedFloat64Array, .variant_type = .packed_float64_array },
    .{ .Type = builtins.PackedStringArray, .variant_type = .packed_string_array },
    .{ .Type = builtins.PackedVector2Array, .variant_type = .packed_vector2_array },
    .{ .Type = builtins.PackedVector3Array, .variant_type = .packed_vector3_array },
    .{ .Type = builtins.PackedColorArray, .variant_type = .packed_color_array },
    .{ .Type = builtins.PackedVector4Array, .variant_type = .packed_vector4_array },
};

const packed_array_types = [_]type{
    builtins.PackedByteArray,
    builtins.PackedInt32Array,
    builtins.PackedInt64Array,
    builtins.PackedFloat32Array,
    builtins.PackedFloat64Array,
    builtins.PackedStringArray,
    builtins.PackedVector2Array,
    builtins.PackedVector3Array,
    builtins.PackedColorArray,
    builtins.PackedVector4Array,
};

/// `VariantType` of a codegen builtin `T`, or `null` for non-builtin types.
fn builtinVariantType(comptime T: type) ?interface.VariantType {
    inline for (builtin_mappings) |mapping| {
        if (T == mapping.Type) return mapping.variant_type;
    }
    return null;
}

fn isPackedArray(comptime T: type) bool {
    inline for (packed_array_types) |Packed| {
        if (T == Packed) return true;
    }
    return false;
}

/// Builtins the engine stores behind an owned heap allocation rather than in
/// the inline Variant data area.
const heap_builtin_types = [_]type{
    builtins.AABB,
    builtins.Basis,
    builtins.Projection,
    builtins.Transform2D,
    builtins.Transform3D,
};

fn isHeapBuiltin(comptime T: type) bool {
    inline for (heap_builtin_types) |Heap| {
        if (T == Heap) return true;
    }
    return false;
}

/// `VariantType` for a scalar type (bool, int, float, enum or bitfield).
fn scalarVariantType(comptime T: type) interface.VariantType {
    return switch (@typeInfo(T)) {
        .bool => .bool,
        .float => .float,
        .int, .@"enum" => .int,
        .@"struct" => |info| blk: {
            _ = info.backing_integer orelse
                @compileError("Not a canonical scalar type: " ++ @typeName(T));
            break :blk .int; // packed bitfield
        },
        else => @compileError("Not a canonical scalar type: " ++ @typeName(T)),
    };
}

/// Reads a scalar value out of Variant data storage.
///
/// The Variant `int` payload is an `i64`. Narrow integer, enum and bitfield
/// targets return `null` when the payload does not fit; unsigned 64-bit targets
/// are bit-preserved so values written from them round-trip exactly.
fn scalarFromData(comptime T: type, data: Variant.Data) ?T {
    return switch (@typeInfo(T)) {
        .bool => abi.Box(T).narrow(@intFromBool(data.bool)),
        .float => abi.Box(T).narrow(data.float),
        .int => intFromVariant(T, data.int),
        .@"enum" => |info| {
            const backing = intFromVariant(info.tag_type, data.int) orelse return null;
            return std.enums.fromInt(T, backing);
        },
        .@"struct" => |info| {
            const Backing = info.backing_integer orelse
                @compileError("Not a canonical scalar type: " ++ @typeName(T));
            const backing = intFromVariant(Backing, data.int) orelse return null;
            return @bitCast(backing);
        },
        else => @compileError("Not a canonical scalar type: " ++ @typeName(T)),
    };
}

/// Converts the Variant `int` payload to a scalar integer type, rejecting
/// values outside its range. Unsigned 64-bit targets are deliberately
/// bit-preserving: the Variant stores their payload as `i64`, and `scalarData`
/// bit-casts it (this includes `u64` and `usize` on 64-bit targets).
fn intFromVariant(comptime T: type, raw: i64) ?T {
    const info = @typeInfo(T).int;
    if (comptime info.bits == 64 and info.signedness == .unsigned) return @bitCast(raw);
    return std.math.cast(T, raw);
}

/// Writes a scalar value into Variant data storage.
fn scalarData(comptime T: type, value: T) Variant.Data {
    return switch (@typeInfo(T)) {
        .bool => .{ .bool = abi.Box(T).widen(value) != 0 },
        .float => .{ .float = abi.Box(T).widen(value) },
        else => .{ .int = canonicalToI64(abi.Box(T).widen(value)) },
    };
}

/// Fits a canonical scalar slot into the Variant `int` storage (`i64`).
fn canonicalToI64(raw: anytype) i64 {
    return if (comptime @TypeOf(raw) == u64) @bitCast(raw) else @intCast(raw);
}

fn wrapScalar(comptime T: type, value: T) Variant {
    return .{
        .tag = scalarVariantType(T),
        .data = scalarData(T, value),
    };
}

fn wrapBuiltin(comptime T: type, comptime variant_type: interface.VariantType, value: T) Variant {
    comptime {
        // `Variant.Data` holds the engine's inline value; its size follows the
        // precision configuration. Some builtins are larger than that and the
        // engine stores a pointer to an owned heap value instead; those cannot
        // be borrowed by writing the value, and their Variant owns/destroys that
        // allocation.
        if (@sizeOf(T) > @sizeOf(Variant.Data)) {
            @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
                ": the engine keeps it behind an owned heap allocation. Use Variant.init for an owned Variant.");
        }
        if (@alignOf(T) > @alignOf(Variant.Data)) {
            @compileError("Variant.wrap cannot store " ++ @typeName(T) ++ " in Variant data storage (alignment)");
        }
    }

    var result: Variant = .{ .tag = variant_type, .data = std.mem.zeroes(Variant.Data) };
    @as(*T, @ptrCast(&result.data)).* = value;
    return result;
}

/// Borrowed object Variant for an engine object class pointer.
fn wrapEngineObject(comptime T: type, value: *const T) Variant {
    const object: *Object = @constCast(@as(*const Object, @ptrCast(value)));
    return borrowedObjectVariant(object);
}

/// Borrowed object Variant for a Zig extension class pointer.
///
/// The Variant stores the ultimate engine base object, not the Zig instance;
/// extension instances are only reachable through that engine object's instance
/// binding (see `Variant.as`).
fn wrapExtensionObject(comptime T: type, value: *const T) Variant {
    const base = reflect.engineBasePointer(T, value);
    return borrowedObjectVariant(@ptrCast(base));
}

fn borrowedObjectVariant(object: *Object) Variant {
    return objectVariant(objectInstanceId(object), object);
}

fn objectVariant(instance_id: u64, object: *Object) Variant {
    return .{
        .tag = .object,
        .data = .{ .object = .{
            .obj_id = .{ .id = instance_id },
            .object = object,
        } },
    };
}

fn initBuiltin(comptime T: type, comptime variant_type: interface.VariantType, value: T) Variant {
    var binding_value = value.toBinding();
    var result: Variant = undefined;
    fromTypeConstructor(variant_type)(@ptrCast(&result), @ptrCast(&binding_value));
    return result;
}

/// Owned object Variant for an object pointer of either class kind.
///
/// `target` is the pointer's `reflect.objectTarget` classification, computed once
/// by `init`; only extension-class targets need the Base marker walk.
fn initObjectPointer(comptime target: reflect.ObjectTarget, value: anytype) Variant {
    const Class = target.class;

    const instance = nonNullObjectPointer(Class, target, value) orelse return Variant.nil;

    // The Variant stores an engine object. An engine class pointer is already
    // that object; an extension instance belongs to the engine object its Base
    // marker chain resolves to.
    const object: *Object = if (comptime target.kind == .engine)
        @ptrCast(instance)
    else
        @ptrCast(reflect.engineBasePointer(Class, instance));

    return initEngineObject(object);
}

/// Extracts the non-null pointee of an object-pointer value (`*C`, `*const C`,
/// `?*C`, `?*const C`) as a mutable `*Class`; null for a null optional.
fn nonNullObjectPointer(
    comptime Class: type,
    comptime target: reflect.ObjectTarget,
    value: anytype,
) ?*Class {
    if (comptime target.optional) {
        const item = value orelse return null;
        return @constCast(@as(*const Class, @ptrCast(item)));
    }
    return @constCast(@as(*const Class, @ptrCast(value)));
}

/// Owned object Variant for an engine object (also the engine base behind an
/// extension class).
fn initEngineObject(object: *Object) Variant {
    const instance_id = objectInstanceId(object);

    // Do not use `get_variant_from_type_constructor(.object)` here: Godot's
    // `Variant(const Object*)` calls `RefCounted::init_ref()`, whose
    // creation-reference accounting may either consume an unclaimed creation
    // reference (sharing the caller's ownership) or fail with refcount 0 and
    // store an empty ObjData. Build the object data ourselves and add one plain
    // owning reference for RefCounted objects; Variant cleanup unrefs it.
    if (instance_id & object_id_ref_counted_bit != 0) {
        if (!addObjectReference(object)) return Variant.nil;
    }

    return objectVariant(instance_id, object);
}

/// Adds one owning reference to a runtime-RefCounted engine object (the
/// instance ID ref-counted bit). Returns false when the engine reports the
/// object as no longer referenceable.
fn addObjectReference(object: *Object) bool {
    return classes.core.RefCounted.reference(@ptrCast(object));
}

fn asBuiltin(comptime T: type, comptime variant_type: interface.VariantType, self: *const Variant) T {
    const Binding = BindingType(T);
    // The engine writes the ABI representation of the binding builtin; the
    // codegen builtin is ABI-compatible and converts through `fromBinding`.
    var binding_value: Binding = undefined;
    toTypeConstructor(variant_type)(@ptrCast(&binding_value), @ptrCast(@constCast(self)));
    return T.fromBinding(binding_value);
}

/// Extracts the engine object pointer or registered extension instance behind
/// the object pointer type `T`.
///
/// `target` is the pointer's `reflect.objectTarget` classification, computed once
/// by `as`; only extension-class targets resolve the engine base class.
fn asObjectPointer(
    comptime T: type,
    comptime target: reflect.ObjectTarget,
    self: *const Variant,
) ?T {
    if (comptime target.optional) {
        @compileError("Variant.as returns ?T, so pass a non-optional object pointer, found: " ++ @typeName(T));
    }

    if (self.tag != .object) return null;

    var object: ?*Object = null;
    toTypeConstructor(.object)(@ptrCast(&object), @ptrCast(@constCast(self)));
    const engine_object = object orelse return null;

    if (comptime target.kind == .engine) {
        const value: T = @ptrCast(engine_object);
        return value;
    } else {
        const Class = target.class;
        const Base = comptime reflect.EngineBaseType(Class);
        const base: *Base = @ptrCast(engine_object);
        const instance = base.asInstance(Class) orelse return null;
        const value: T = @ptrCast(instance);
        return value;
    }
}

fn unsupportedWrap(comptime T: type) noreturn {
    if (comptime reflect.isClassType(T)) {
        @compileError("Variant.wrap expects `*T` for class type " ++ @typeName(T) ++
            "; pass a pointer to the class instance");
    }
    @compileError("Variant.wrap does not support type: " ++ @typeName(T));
}

fn unsupportedInit(comptime T: type) noreturn {
    if (comptime reflect.isClassType(T)) {
        @compileError("Variant.init expects a pointer for class type " ++ @typeName(T) ++
            "; pass *T or ?*T instead of the class value type");
    }
    @compileError("Variant.init does not support type: " ++ @typeName(T));
}

fn unsupportedAs(comptime T: type) noreturn {
    if (comptime reflect.isClassType(T)) {
        @compileError("Variant.as expects a pointer for class type " ++ @typeName(T) ++ "; pass *T");
    }
    @compileError("Variant.as does not support type: " ++ @typeName(T));
}

/// Binding builtin type produced by `T.toBinding`.
fn BindingType(comptime T: type) type {
    const fn_info = @typeInfo(@TypeOf(T.toBinding)).@"fn";
    return fn_info.return_type orelse
        @compileError("Builtin " ++ @typeName(T) ++ " has no binding conversion type");
}

/// Lazily cached `get_variant_from_type_constructor` result. The GDExtension
/// callback pointer is stable for the dispatcher lifetime; only the first call
/// for a given VariantType pays the lookup. First-use resolution is unsynchronized,
/// matching the generated binding method caches; call after dispatcher init.
fn fromTypeConstructor(comptime variant_type: interface.VariantType) std.meta.Child(interface.VariantFromTypeConstructorFunc) {
    const From = struct {
        pub const v_type = variant_type;
        pub var from_func: interface.VariantFromTypeConstructorFunc = null;
    };
    if (From.from_func == null) {
        @branchHint(.cold);
        From.from_func = runtime.dispatch(.get_variant_from_type_constructor, .{variant_type}) orelse
            @panic("Godot does not expose a Variant from-type constructor for this type");
    }
    return From.from_func orelse unreachable;
}

/// Lazily cached `get_variant_to_type_constructor` result. Like the from-type
/// cache, first-use resolution is unsynchronized.
fn toTypeConstructor(comptime variant_type: interface.VariantType) std.meta.Child(interface.TypeFromVariantConstructorFunc) {
    const To = struct {
        pub const v_type = variant_type;
        pub var to_func: interface.TypeFromVariantConstructorFunc = null;
    };
    if (To.to_func == null) {
        @branchHint(.cold);
        To.to_func = runtime.dispatch(.get_variant_to_type_constructor, .{variant_type}) orelse
            @panic("Godot does not expose a Variant to-type constructor for this type");
    }
    return To.to_func orelse unreachable;
}

fn objectInstanceId(object: *Object) u64 {
    return Object.getInstanceId(object);
}

/// Godot's `ObjectID::is_ref_counted()` is bit 63 of the 64-bit instance ID
/// (`OBJECTDB_REFERENCE_BIT`, set by `ObjectDB::add_instance`). It is also the
/// flag Variant object cleanup (`ObjData::unref`) reads to decide whether it
/// owns a reference, so it is the correct runtime test for hand-written
/// Variant object construction.
const object_id_ref_counted_bit: u64 = @as(u64, 1) << 63;

const std = @import("std");

const abi = @import("../abi.zig");
const reflect = @import("../reflect/reflect.zig");
const runtime = @import("../runtime.zig");

const AABB = @import("aabb.zig").AABB;
const Array = builtins.Array;
const Basis = @import("basis.zig").Basis;
const Callable = builtins.Callable;
const Color = @import("color.zig").Color;
const Dictionary = builtins.Dictionary;
const NodePath = builtins.NodePath;
const Plane = @import("plane.zig").Plane;
const Projection = @import("projection.zig").Projection;
const Quaternion = @import("quaternion.zig").Quaternion;
const rect = @import("rect.zig");
const Rect2 = rect.Rect2;
const Rect2i = rect.Rect2i;
const RID = @import("rid.zig").RID;
const Signal = builtins.Signal;
const String = builtins.String;
const StringName = builtins.StringName;
const Transform2D = @import("transform2d.zig").Transform2D;
const Transform3D = @import("transform3d.zig").Transform3D;
const vector = @import("vector.zig");
const Vector2 = vector.Vector2;
const Vector2i = vector.Vector2i;
const Vector3 = vector.Vector3;
const Vector3i = vector.Vector3i;
const Vector4 = vector.Vector4;
const Vector4i = vector.Vector4i;

const bindings = @import("bindings");
const Object = classes.core.Object;
const interface = bindings.interface;
const native = bindings.native;

const builtins = @import("builtins.zig");
const classes = @import("../classes/classes.zig");
