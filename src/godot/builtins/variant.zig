//! Hand-written `Variant`: borrowed views, owning construction, typed extraction.
//! The engine ABI and ownership rules are documented in docs/variants.md.

pub const Variant = extern struct {
    pub const GodotClassName = "Variant";

    tag: interface.VariantType align(@alignOf(bindings.builtins.Variant)),
    data: Data align(@alignOf(bindings.builtins.Variant)),

    /// Engine Variant data payload. The layout is owned by the generated
    /// binding layer; the codegen wrapper uses the same ABI-compatible type.
    pub const Data = bindings.builtins.variant.Variant.Data;

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

    /// The GDExtension Variant type of `T`, or null when it has none.
    pub fn typeFor(comptime T: type) ?interface.VariantType {
        if (comptime T == Variant) return null;
        if (comptime abi.Box(T).canonical) return scalarVariantTypeFor(T);
        if (comptime builtinVariantType(T)) |variant_type| return variant_type;
        if (comptime reflect.objectTarget(T) != null) return .object;
        return null;
    }

    /// Creates a borrowed Variant view of `value`. Inline values are copied into
    /// the payload; pointers borrow. Packed arrays and heap-backed builtins are
    /// rejected; use `init` for an owning Variant. See docs/variants.md.
    pub fn wrap(comptime T: type, value: anytype) Variant {
        const VT = @TypeOf(value);
        if (VT == T) return wrapValue(T, value);
        if (VT == @TypeOf(null)) {
            if (comptime reflect.objectTarget(T)) |target| {
                if (comptime target.optional) return Variant.nil;
            }
            @compileError("Variant.wrap: null is only a valid raw value for an optional object pointer type");
        }
        if (VT == comptime_int) {
            if (comptime abi.Box(T).canonical) return wrapValue(T, @as(T, value));
        }
        if (VT == comptime_float) {
            if (comptime abi.Box(T).canonical and @typeInfo(T) == .float) return wrapValue(T, @as(T, value));
        }
        if (VT == @TypeOf(.enum_literal)) {
            if (comptime @typeInfo(T) == .@"enum") return wrapValue(T, @as(T, value));
        }
        if (VT != *const T and VT != *T and VT != ?*T and VT != ?*const T) {
            @compileError(std.fmt.comptimePrint(
                "Variant.wrap expects a {s} value, a pointer to {s}, or an optional pointer; found: {s}",
                .{ @typeName(T), @typeName(T), @typeName(VT) },
            ));
        }

        validateBorrowable(T, false);

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

    /// Borrows a raw value when its Variant representation is already inline or
    /// is the borrowed object pointer itself.
    ///
    /// Scalars and inline plain builtins are copied into the Variant data area,
    /// so the result has no source lifetime. Object pointers are borrowed as
    /// usual. Owned deinit-types and heap-backed builtins must be passed to
    /// `init` instead; copying their bytes would alias or lose ownership.
    fn wrapValue(comptime T: type, value: T) Variant {
        if (comptime abi.Box(T).canonical) {
            return wrapScalar(T, value);
        }
        if (comptime T == Variant) {
            @compileError("Variant.wrap cannot borrow a Variant by value; pass a pointer to borrow it, or use clone/init for an owned Variant");
        }
        if (comptime builtinVariantType(T)) |variant_type| {
            validateBorrowable(T, true);
            return wrapBuiltin(T, variant_type, value);
        }
        if (comptime reflect.objectTarget(T)) |target| {
            return wrapObjectValue(T, target, value);
        }
        unsupportedWrap(T);
    }

    /// Borrows a raw object pointer, including an optional pointer.
    fn wrapObjectValue(comptime T: type, comptime target: reflect.ObjectTarget, value: T) Variant {
        const Class = target.class;
        const pointer: *const Class = if (comptime target.optional)
            @ptrCast(value orelse return Variant.nil)
        else
            @ptrCast(value);
        return if (comptime target.kind == .engine)
            wrapEngineObject(Class, pointer)
        else
            wrapExtensionObject(Class, pointer);
    }

    /// Creates an owning Variant from `value`. The value remains owned by the
    /// caller; release the result with `deinit`. See docs/variants.md.
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

    /// True for an object-tagged Variant with empty ObjData (id 0).
    pub fn isNullObject(self: *const Variant) bool {
        return self.tag == .object and self.data.object.id.id == 0;
    }

    /// Returns the live object behind an object Variant, or null if the Variant
    /// is not an object or the stored instance id is stale.
    pub fn objectInstance(self: *const Variant) ?*Object {
        if (self.tag != .object) return null;
        const object_id = self.data.object.id.id;
        if (object_id == 0) return null;
        const live = runtime.dispatch(.object_get_instance_from_id, .{object_id});
        const live_ptr: ?*const anyopaque = @ptrCast(live);
        const live_object = live_ptr orelse return null;
        if (@intFromPtr(live_object) != @intFromPtr(self.data.object.object)) return null;
        return @ptrCast(@constCast(live_object));
    }

    /// Extracts `T` when the Variant tag matches exactly. Returns null on a tag
    /// or range mismatch. Owned values must be deinitialized by the caller.
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

    /// Creates an owning Variant from `value` for the declared engine type.
    ///
    /// Accepts the declared type, coercible literals, and, for object types, an
    /// extending engine class pointer or an extension instance whose engine base
    /// extends the declared class. An extension-declared class accepts only that
    /// exact instance. A nullable value that is null becomes `nil`, even for a
    /// non-optional declared type.
    pub fn initDeclared(comptime Declared: type, value: anytype) Variant {
        if (comptime reflect.objectTarget(Declared)) |target| {
            return initDeclaredObject(Declared, target, value);
        }
        return initDeclaredPlain(Declared, value);
    }

    /// Extracts `Declared` from this Variant, or returns null when it does not
    /// hold that type. `nil` becomes null for optional object pointers. Engine
    /// objects are checked with `Object.isClass`, so subclasses pass; extension
    /// values resolve only their exact registered instance.
    pub fn asDeclared(self: *const Variant, comptime Declared: type) ?Declared {
        if (comptime reflect.objectTarget(Declared)) |target| {
            return asDeclaredObject(self, Declared, target);
        }
        if (comptime Declared != Variant and typeFor(Declared) == null) {
            @compileError("Variant.asDeclared: '" ++ @typeName(Declared) ++ "' has no Variant representation");
        }
        return self.as(Declared);
    }

    /// Creates an owning shallow copy of the Variant.
    pub fn clone(self: *const Variant) Variant {
        var result: Variant = undefined;
        runtime.dispatch(.variant_new_copy, .{
            @as(interface.UninitializedVariantPtr, @ptrCast(&result)),
            @as(interface.ConstVariantPtr, @ptrCast(self)),
        });
        return result;
    }

    /// Destroys an owning Variant and leaves it nil. Never call this on a
    /// borrowed `wrap` result.
    pub fn deinit(self: *Variant) void {
        runtime.dispatch(.variant_destroy, .{@as(interface.VariantPtr, @ptrCast(self))});
        self.* = nil;
    }

    /// Precomputed nil Variant with no engine-managed references.
    pub const nil: Variant = .{ .tag = .nil, .data = .{ .nil = {} } };
};

// Conversion helpers

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

fn builtinVariantType(comptime T: type) ?interface.VariantType {
    inline for (builtin_mappings) |mapping| {
        if (T == mapping.Type) return mapping.variant_type;
    }
    return null;
}

fn scalarVariantTypeFor(comptime T: type) ?interface.VariantType {
    const result: ?interface.VariantType = switch (@typeInfo(T)) {
        .bool => .bool,
        .float => .float,
        .int => |info| if (info.bits > 64) null else .int,
        .@"enum" => |info| if (@bitSizeOf(info.tag_type) > 64) null else .int,
        .@"struct" => |info| blk: {
            const Backing = info.backing_integer orelse break :blk null;
            break :blk if (@bitSizeOf(Backing) > 64) null else .int;
        },
        else => null,
    };
    return result;
}

fn scalarVariantType(comptime T: type) interface.VariantType {
    return comptime blk: {
        if (scalarVariantTypeFor(T)) |variant_type| break :blk variant_type;
        @compileError("Variant payloads do not support scalar types wider than 64 bits: " ++ @typeName(T));
    };
}

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

fn intFromVariant(comptime T: type, raw: i64) ?T {
    const info = @typeInfo(T).int;
    if (comptime info.bits == 64 and info.signedness == .unsigned) return @bitCast(raw);
    return std.math.cast(T, raw);
}

fn scalarData(comptime T: type, value: T) Variant.Data {
    return switch (@typeInfo(T)) {
        .bool => .{ .bool = abi.Box(T).widen(value) != 0 },
        .float => .{ .float = abi.Box(T).widen(value) },
        else => .{ .int = canonicalToI64(abi.Box(T).widen(value)) },
    };
}

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

fn wrapEngineObject(comptime T: type, value: *const T) Variant {
    const object: *Object = @constCast(@as(*const Object, @ptrCast(value)));
    return borrowedObjectVariant(object);
}

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
            .id = .{ .id = instance_id },
            .object = @ptrCast(object),
        } },
    };
}

fn initBuiltin(comptime T: type, comptime variant_type: interface.VariantType, value: T) Variant {
    var binding_value = value.toBinding();
    var result: Variant = undefined;
    fromTypeConstructor(variant_type)(@ptrCast(&result), @ptrCast(&binding_value));
    return result;
}

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

fn initEngineObject(object: *Object) Variant {
    const instance_id = objectInstanceId(object);

    // Build the object data ourselves and add one plain owning reference for
    // RefCounted objects; Variant cleanup unrefs it. The engine Variant
    // constructor goes through `RefCounted::init_ref()`, which is not the
    // ownership shape this path needs.
    if (instance_id & object_id_ref_counted_bit != 0) {
        if (!ownership.retainObjectReference(object)) return Variant.nil;
    }

    return objectVariant(instance_id, object);
}

fn asBuiltin(comptime T: type, comptime variant_type: interface.VariantType, self: *const Variant) T {
    const Binding = BindingType(T);
    // The engine writes the ABI representation of the binding builtin; the
    // codegen builtin is ABI-compatible and converts through `fromBinding`.
    var binding_value: Binding = undefined;
    toTypeConstructor(variant_type)(@ptrCast(&binding_value), @ptrCast(@constCast(self)));
    return T.fromBinding(binding_value);
}

fn asObjectPointer(
    comptime T: type,
    comptime target: reflect.ObjectTarget,
    self: *const Variant,
) ?T {
    if (comptime target.optional) {
        @compileError("Variant.as returns ?T, so pass a non-optional object pointer, found: " ++ @typeName(T));
    }

    const engine_object = self.objectInstance() orelse return null;

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

fn validateBorrowable(comptime T: type, comptime by_value: bool) void {
    if (comptime bindings.builtins.traits.isPackedArray(T)) {
        @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
            ": packed arrays are copy-on-write engine values. Use Variant.init for an owned Variant.");
    }
    if (comptime bindings.builtins.traits.isHeapBuiltin(T)) {
        @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
            ": the engine keeps it behind an owned heap allocation. Use Variant.init for an owned Variant.");
    }
    if (by_value and @hasDecl(T, "deinit")) {
        @compileError("Variant.wrap cannot borrow " ++ @typeName(T) ++
            " by value: it owns engine storage. Pass a pointer to borrow it, or use Variant.init for an owned Variant.");
    }
}

fn BindingType(comptime T: type) type {
    const fn_info = @typeInfo(@TypeOf(T.toBinding)).@"fn";
    return fn_info.return_type orelse
        @compileError("Builtin " ++ @typeName(T) ++ " has no binding conversion type");
}

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

fn initDeclaredPlain(comptime Declared: type, value: anytype) Variant {
    const ValueT = @TypeOf(value);
    if (comptime ValueT == Declared) return Variant.init(Declared, value);
    if (comptime ValueT == comptime_int) return Variant.init(Declared, @as(Declared, value));
    if (comptime ValueT == comptime_float) return Variant.init(Declared, @as(Declared, value));
    if (comptime ValueT == @TypeOf(.enum_literal) and @typeInfo(Declared) == .@"enum") {
        return Variant.init(Declared, @as(Declared, value));
    }
    @compileError(std.fmt.comptimePrint(
        "Variant.initDeclared expects {s}, found: {s}",
        .{ @typeName(Declared), @typeName(ValueT) },
    ));
}

fn initDeclaredObject(
    comptime Declared: type,
    comptime target: reflect.ObjectTarget,
    value: anytype,
) Variant {
    const DeclaredClass = target.class;
    const ValueT = @TypeOf(value);

    if (comptime ValueT == @TypeOf(null)) {
        if (comptime !target.optional) @compileError(
            "Variant.initDeclared: " ++ @typeName(Declared) ++ " is not optional; pass a class instance instead of null",
        );
        return Variant.nil;
    }

    const value_target = comptime reflect.objectTarget(ValueT) orelse @compileError(std.fmt.comptimePrint(
        "Variant.initDeclared expects an instance over {s}, found: {s}",
        .{ @typeName(DeclaredClass), @typeName(ValueT) },
    ));

    if (comptime target.kind == .extension) {
        // Extension declarations are exact-class: the instance binding is per
        // class, so the instance itself is required; `init` walks its Base chain.
        if (comptime value_target.class != DeclaredClass) @compileError(std.fmt.comptimePrint(
            "Variant.initDeclared: '{s}' is an extension class; pass that exact instance, or declare an engine base class instead. Found: {s}",
            .{ @typeName(DeclaredClass), @typeName(ValueT) },
        ));
        const instance = nonNullObjectPointer(DeclaredClass, value_target, value) orelse return Variant.nil;
        return Variant.init(Declared, instance);
    }

    const ValueClass = value_target.class;
    const EngineBase = comptime reflect.EngineBaseType(ValueClass);
    if (comptime !reflect.inheritsFrom(EngineBase, DeclaredClass)) @compileError(std.fmt.comptimePrint(
        "Variant.initDeclared expects '{s}', but '{s}' resolves to engine base '{s}', which does not extend it",
        .{ @typeName(DeclaredClass), @typeName(ValueClass), @typeName(EngineBase) },
    ));

    const raw: *ValueClass = nonNullObjectPointer(ValueClass, value_target, value) orelse
        return Variant.nil;
    const instance: *DeclaredClass = if (comptime value_target.kind == .engine)
        @ptrCast(raw)
    else
        @ptrCast(reflect.engineBasePointer(ValueClass, raw));

    return Variant.init(Declared, instance);
}

fn asDeclaredObject(
    self: *const Variant,
    comptime Declared: type,
    comptime target: reflect.ObjectTarget,
) ?Declared {
    const Inner = if (comptime target.optional) @typeInfo(Declared).optional.child else Declared;
    if (comptime target.optional) {
        if (self.tag == .nil or self.isNullObject()) {
            // Return a null *value*, not a null outer optional: `null` here
            // means "the Variant does not hold the declared type".
            const empty: Declared = null;
            return empty;
        }
    }
    const inner: Inner = self.as(Inner) orelse return null;
    if (comptime target.kind == .engine) {
        if (!isDeclaredEngineClass(target, inner)) return null;
    }
    return inner;
}

/// Runtime class check for an engine object value; subclasses are accepted.
fn isDeclaredEngineClass(comptime target: reflect.ObjectTarget, object: anytype) bool {
    const class_name = builtins.StringName.fromComptimeLatin1(
        comptime reflect.className(target.class),
    );
    return Object.isClass(@ptrCast(object), class_name);
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const abi = @import("../abi.zig");
const classes = @import("../classes/classes.zig");
const Object = classes.core.Object;
const ownership = @import("../ownership.zig");
const reflect = @import("../reflect/reflect.zig");
const runtime = @import("../runtime.zig");
const builtins = @import("builtins.zig");
