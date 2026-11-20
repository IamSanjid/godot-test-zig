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

comptime {
    bindings.builtins.variant.checkTypeLayout(Variant);

    // Variant::_data is alignas(8) in every configuration; the data area starts at 8.
    if (@alignOf(Variant) != 8) @compileError("Variant alignment must be 8");
    if (@offsetOf(Variant, "data") != 8) @compileError("Variant data must start at offset 8");
    const expected_data_size = @sizeOf(Variant) - 8;
    if (@sizeOf(Variant.Data) != expected_data_size) @compileError("Variant Data size does not match the engine layout");
}

comptime {
    @setEvalBranchQuota(1_000_000);
    // The type mapping is part of the public contract: every codegen builtin type
    // must have exactly its GDExtension VariantType, scalars must map to the
    // canonical scalar tags, object class pointers must map to `object`, and
    // `Variant` itself must stay transparent (no VariantType).
    for (builtin_mappings) |mapping| {
        if (Variant.typeFor(mapping.Type) != mapping.variant_type) {
            @compileError("Variant.typeFor is missing or mis-maps builtin: " ++ @typeName(mapping.Type));
        }
        const Binding = BindingType(mapping.Type);
        if (bindings.builtins.traits.kindOf(mapping.Type) != bindings.builtins.traits.kindOf(Binding)) {
            @compileError("codegen/binding builtin classification mismatch: " ++ @typeName(mapping.Type));
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
    if (Variant.typeFor(i128) != null) @compileError("Variant.typeFor must reject scalar types wider than 64 bits");
    const WideEnum = enum(u128) { a };
    if (Variant.typeFor(WideEnum) != null) @compileError("Variant.typeFor must reject enums wider than 64 bits");

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
            padding0: u31 = 0,
        };
        if (Variant.typeFor(Mode) != .int) @compileError("Variant.typeFor must map enums to .int");
        if (Variant.typeFor(Flags) != .int) @compileError("Variant.typeFor must map readable bitfields to .int");
    }
}

comptime {
    // Compile-only coverage for object and builtin conversion.
    const Coverage = struct {
        fn FakeBase(comptime B: type) type {
            return struct {
                pub const BaseFor = B;

                base_ptr: *B = undefined,

                pub fn get(self: *const @This()) *B {
                    return self.base_ptr;
                }

                pub fn set(self: *@This(), value: *B) void {
                    self.base_ptr = value;
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

            // Raw values: scalars and inline plain builtins are copied into the
            // borrowed Variant data; raw object pointers are borrowed directly.
            _ = Variant.wrap(i32, 7);
            _ = Variant.wrap(f32, 1.5);
            _ = Variant.wrap(builtins.Vector2, builtins.Vector2.zero);
            _ = Variant.wrap(*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.wrap(?*const classes.core.Node, null);
            const Mode = enum(u2) { a, b };
            _ = Variant.wrap(Mode, .b);

            // Engine class pointers: existing pointer behavior.
            _ = Variant.wrap(classes.core.Object, @as(*const classes.core.Object, undefined));
            _ = Variant.wrap(classes.core.Node, @as(?*const classes.core.Node, null));
            _ = Variant.init(*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.init(?*classes.core.RefCounted, null);
            _ = variant.as(*classes.core.Object);
            _ = variant.as(*const classes.core.Node);
            _ = variant.objectInstance();
            _ = variant.isNullObject();

            // Direct extension class.
            _ = Variant.wrap(*const DirectExtension, @as(*const DirectExtension, undefined));
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

        fn rawWrapInline(dispatcher: *const runtime.DefaultDispatcher) void {
            inline for (.{
                bindings.builtins.String,
                bindings.builtins.StringName,
                bindings.builtins.NodePath,
                bindings.builtins.RID,
                bindings.builtins.Callable,
                bindings.builtins.Signal,
                bindings.builtins.Array,
                bindings.builtins.Dictionary,
                bindings.builtins.Vector2,
                bindings.builtins.Vector2i,
                bindings.builtins.Vector3,
                bindings.builtins.Vector3i,
                bindings.builtins.Vector4,
                bindings.builtins.Vector4i,
                bindings.builtins.Rect2,
                bindings.builtins.Rect2i,
                bindings.builtins.Plane,
                bindings.builtins.Quaternion,
                bindings.builtins.Color,
            }) |Inline| {
                var value: Inline = undefined;
                _ = bindings.builtins.Variant.wrap(dispatcher, Inline, &value);
            }
        }

        fn scalarCoverage(variant: *const Variant) void {
            const Mode = enum(u32) { a = 0, b = 1 };
            const Flags = bitpack struct(u32) {
                first: bool = false,
                padding0: u31 = 0,
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
    _ = &Coverage.rawWrapInline;
    _ = &Coverage.scalarCoverage;
    _ = &Coverage.builtinCoverage;
}

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

const std = @import("std");

const bindings = @import("bindings");

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

const Object = classes.core.Object;
const interface = bindings.interface;
const native = bindings.native;

const builtins = @import("builtins.zig");
const classes = @import("../classes/classes.zig");
