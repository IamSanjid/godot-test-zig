//! Tests and compile-only coverage for the hand-written `Variant`.

/// A builtin type and the GDExtension Variant type it occupies.
const BuiltinMapping = struct {
    Type: type,
    variant_type: interface.VariantType,
};

/// Every codegen builtin type in `godot.builtins`, mapped to its Variant type.
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

fn bindingType(comptime T: type) type {
    const fn_info = @typeInfo(@TypeOf(T.toBinding)).@"fn";
    return fn_info.return_type orelse
        @compileError("Builtin " ++ @typeName(T) ++ " has no binding conversion type");
}
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
        const Binding = bindingType(mapping.Type);
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
            _ = Variant.borrow(i32, 7);
            _ = Variant.borrow(f32, 1.5);
            _ = Variant.borrow(builtins.Vector2, builtins.Vector2.zero);
            _ = Variant.borrow(*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.borrow(?*const classes.core.Node, null);
            const Mode = enum(u2) { a, b };
            _ = Variant.borrow(Mode, .b);

            // Engine class pointers: existing pointer behavior.
            _ = Variant.borrow(classes.core.Object, @as(*const classes.core.Object, undefined));
            _ = Variant.borrow(classes.core.Node, @as(?*const classes.core.Node, null));
            _ = Variant.init(*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.init(?*classes.core.RefCounted, null);
            _ = variant.as(*classes.core.Object);
            _ = variant.as(*const classes.core.Node);
            _ = variant.objectInstance();
            _ = variant.isNullObject();

            // Direct extension class.
            _ = Variant.borrow(*const DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.borrow(DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.borrow(DirectExtension, @as(?*DirectExtension, null));
            _ = Variant.init(*DirectExtension, @as(*DirectExtension, undefined));
            _ = Variant.init(*const DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.init(?*const DirectExtension, null);
            _ = Variant.init(?*DirectExtension, @as(?*DirectExtension, null));
            _ = variant.as(*DirectExtension);
            _ = variant.as(*const DirectExtension);

            // Extension -> extension chain.
            _ = Variant.borrow(ChainedExtension, @as(*const ChainedExtension, undefined));
            _ = Variant.init(*ChainedExtension, @as(*ChainedExtension, undefined));
            _ = Variant.init(*const ChainedExtension, @as(*const ChainedExtension, undefined));
            _ = variant.as(*ChainedExtension);

            if (comptime reflect.isExtensionClass(DirectExtension) == false) {
                @compileError("Variant.borrow/init extension conversion: direct extension class was not recognized");
            }
            if (comptime Variant.typeFor(*DirectExtension) == null) {
                @compileError("Variant.typeFor must map direct extension class pointers to .object");
            }
            if (comptime Variant.typeFor(?*ChainedExtension) == null) {
                @compileError("Variant.typeFor must map chained extension class pointers to .object");
            }

            // Declared-type conversions, declared and inferred forms.
            _ = Variant.initDeclared(i32, 7);
            _ = Variant.initDeclared(f32, 1.5);
            _ = Variant.initDeclared(?*classes.core.Node, null);
            _ = Variant.initDeclared(?*classes.core.Node, @as(*classes.core.Node, undefined));
            _ = Variant.initDeclared(?*classes.core.Node, @as(*DirectExtension, undefined));
            _ = Variant.initDeclared(*classes.core.Object, @as(*classes.core.Node, undefined));
            _ = Variant.initDeclared(*DirectExtension, @as(*DirectExtension, undefined));
            _ = Variant.initDeclared(?*const DirectExtension, @as(*const DirectExtension, undefined));
            _ = Variant.initDeclared(builtins.PackedByteArray, @as(builtins.PackedByteArray, undefined));
            _ = Variant.initDeclared(builtins.Transform3D, @as(builtins.Transform3D, undefined));
            _ = variant.asDeclared(i32);
            _ = variant.asDeclared(?*classes.core.Node);
            _ = variant.asDeclared(*const classes.core.Node);
            _ = variant.asDeclared(*DirectExtension);
            _ = variant.asDeclared(builtins.PackedByteArray);
            _ = variant.asDeclared(builtins.Transform3D);
        }

        // The raw bindgen `Variant.borrow` has a separate generic object branch.
        // Instantiate it here with concrete binding classes so the binding
        // layer's class-pointer cast cannot regress lazily.
        fn rawBorrowEngine(dispatcher: *const runtime.DefaultDispatcher, node: *bindings.classes.core.Node) void {
            _ = bindings.builtins.Variant.borrow(dispatcher, bindings.classes.core.Node, node);
        }

        fn rawBorrowOptional(dispatcher: *const runtime.DefaultDispatcher, node: ?*bindings.classes.core.Node) void {
            _ = bindings.builtins.Variant.borrow(dispatcher, bindings.classes.core.Node, node);
        }

        fn rawBorrowRefCounted(dispatcher: *const runtime.DefaultDispatcher, resource: *bindings.classes.core.RefCounted) void {
            _ = bindings.builtins.Variant.borrow(dispatcher, bindings.classes.core.RefCounted, resource);
        }

        fn rawBorrowInline(dispatcher: *const runtime.DefaultDispatcher) void {
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
                _ = bindings.builtins.Variant.borrow(dispatcher, Inline, &value);
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
    _ = &Coverage.rawBorrowEngine;
    _ = &Coverage.rawBorrowOptional;
    _ = &Coverage.rawBorrowRefCounted;
    _ = &Coverage.rawBorrowInline;
    _ = &Coverage.scalarCoverage;
    _ = &Coverage.builtinCoverage;
}

test "initDeclared coerces literals and null" {
    const int_value = Variant.initDeclared(i32, 7);
    try std.testing.expectEqual(interface.VariantType.int, int_value.tag);
    try std.testing.expectEqual(@as(i64, 7), int_value.as(i32).?);

    const float_value = Variant.initDeclared(f32, 1.5);
    try std.testing.expectEqual(interface.VariantType.float, float_value.tag);
    try std.testing.expectEqual(@as(f32, 1.5), float_value.as(f32).?);

    const Mode = enum(u32) { idle = 0, running = 1 };
    const enum_value = Variant.initDeclared(Mode, .running);
    try std.testing.expectEqual(Mode.running, enum_value.as(Mode).?);

    try std.testing.expectEqual(interface.VariantType.nil, Variant.initDeclared(?*classes.core.Node, null).tag);
}

test "asDeclared round-trips scalars and rejects mismatches" {
    var int_variant = Variant.initDeclared(i32, 13);
    try std.testing.expectEqual(@as(i32, 13), int_variant.asDeclared(i32).?);
    try std.testing.expectEqual(@as(?f32, null), int_variant.asDeclared(f32));

    const Mode = enum(u32) { idle = 0, running = 1 };
    var mode_variant = Variant.initDeclared(Mode, .running);
    try std.testing.expectEqual(Mode.running, mode_variant.asDeclared(Mode).?);

    var nil_variant = Variant.initDeclared(?*classes.core.Node, null);
    const nil_result = nil_variant.asDeclared(?*classes.core.Node);
    try std.testing.expect(nil_result != null); // matched the declared type
    try std.testing.expect(nil_result.? == null); // and holds a null object
}

test "borrow returns a Borrowed view whose accessors alias the Variant" {
    // Borrowed views need no engine and must never be deinitialized.
    const view = Variant.borrow(i32, @as(i32, 7));
    try std.testing.expect(@TypeOf(view) == Variant.Borrowed);
    try std.testing.expectEqual(interface.VariantType.int, view.inner.tag);

    const copy = view.get();
    try std.testing.expectEqual(interface.VariantType.int, copy.tag);
    try std.testing.expectEqual(@as(?i32, 7), copy.as(i32));

    const pointer = view.getPtrConst();
    try std.testing.expect(pointer == &view.inner);
    try std.testing.expectEqual(@as(?i32, 7), pointer.as(i32));
}

test "borrow returns a Borrowed nil view for a null optional object" {
    const view = Variant.borrow(?*classes.core.Node, null);
    try std.testing.expect(@TypeOf(view) == Variant.Borrowed);
    try std.testing.expectEqual(interface.VariantType.nil, view.inner.tag);
    try std.testing.expectEqual(interface.VariantType.nil, view.get().tag);
}

const std = @import("std");

const godot = @import("godot");
const Object = classes.core.Object;
const Variant = godot.builtins.Variant;
const bindings = godot.bindings;
const builtins = godot.builtins;
const classes = godot.classes;
const interface = bindings.interface;
const reflect = godot.reflect;
const runtime = godot.runtime;
