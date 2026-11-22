//! Dynamic property backend: turns `annotations.Property` descriptors into the
//! `ClassCreationInfo6` callbacks. See docs/properties.md.

/// The engine callbacks installed on `ClassCreationInfo6` for one class.
pub const Callbacks = struct {
    set_func: interface.ClassSet = null,
    get_func: interface.ClassGet = null,
    get_property_list_func: interface.ClassGetPropertyList = null,
    free_property_list_func: interface.ClassFreePropertyList2 = null,
};

/// True when `T` declares at least one `Property` field.
pub fn hasPropertyFields(comptime T: type) bool {
    return property.descriptors(T).len != 0;
}

/// Number of descriptors included in `get_property_list` (`usage != 0`).
pub fn visiblePropertyCount(comptime T: type) usize {
    return comptime visibleDescriptorIndices(T).len;
}

/// Forces Variant-type validation for every descriptor, including hidden ones.
fn validateDescriptors(comptime T: type) void {
    inline for (property.descriptors(T)) |desc| {
        _ = requiredVariantType(T, desc);
    }
}

/// Builds the dynamic property callbacks for `T`.
pub fn callbacks(comptime T: type) Callbacks {
    if (comptime !hasPropertyFields(T)) return .{};

    // Hidden descriptors have no list entry but still need a storable Variant
    // type; validate every descriptor before building callbacks.
    comptime validateDescriptors(T);

    const list_visible = comptime visiblePropertyCount(T) != 0;
    return .{
        .set_func = SetCallback(T),
        .get_func = GetCallback(T),
        .get_property_list_func = if (comptime list_visible) GetPropertyListCallback(T) else null,
        .free_property_list_func = if (comptime list_visible) free_property_list else null,
    };
}

/// Process-lifetime `PropertyInfo` table for visible descriptors, in order.
pub fn propertyInfoList(comptime T: type) []const interface.PropertyInfo {
    const visible_count = comptime visiblePropertyCount(T);
    if (comptime visible_count == 0) return &.{};

    const Storage = ListStorage(T);
    if (!Storage.initialized) {
        @branchHint(.cold);
        initList(T);
        Storage.initialized = true;
    }
    return Storage.infos[0..];
}

fn SetCallback(comptime T: type) interface.ClassSet {
    return &struct {
        fn f(
            p_instance: interface.ClassInstancePtr,
            p_name: interface.ConstStringNamePtr,
            p_value: interface.ConstVariantPtr,
        ) callconv(.c) bool {
            const instance: *T = @ptrCast(@alignCast(p_instance orelse return false));
            const name: *const builtins.StringName = @ptrCast(@alignCast(p_name orelse return false));
            const variant: *const builtins.Variant = @ptrCast(@alignCast(p_value orelse return false));

            const descs = comptime property.descriptors(T);
            inline for (descs) |desc| {
                const expected = builtins.StringName.fromComptimeLatin1(desc.godot_name);
                if (name.opEqlStringName(&expected)) {
                    return setProperty(T, desc.field_name, instance, variant);
                }
            }
            return false;
        }
    }.f;
}

fn GetCallback(comptime T: type) interface.ClassGet {
    return &struct {
        fn f(
            p_instance: interface.ClassInstancePtr,
            p_name: interface.ConstStringNamePtr,
            r_ret: interface.VariantPtr,
        ) callconv(.c) bool {
            const instance: *T = @ptrCast(@alignCast(p_instance orelse return false));
            const name: *const builtins.StringName = @ptrCast(@alignCast(p_name orelse return false));

            const descs = comptime property.descriptors(T);
            inline for (descs) |desc| {
                const expected = builtins.StringName.fromComptimeLatin1(desc.godot_name);
                if (name.opEqlStringName(&expected)) {
                    return getProperty(T, desc.field_name, instance, r_ret);
                }
            }
            return false;
        }
    }.f;
}

fn GetPropertyListCallback(comptime T: type) interface.ClassGetPropertyList {
    return &struct {
        fn f(
            _: interface.ClassInstancePtr,
            r_count: [*c]u32,
        ) callconv(.c) ?*const interface.PropertyInfo {
            if (r_count == null) return null;
            const list = propertyInfoList(T);
            r_count[0] = @intCast(list.len);
            return if (list.len == 0) null else @ptrCast(list.ptr);
        }
    }.f;
}

/// The static table owns its entries for the process lifetime.
const free_property_list: interface.ClassFreePropertyList2 = &struct {
    fn f(
        _: interface.ClassInstancePtr,
        _: ?*const interface.PropertyInfo,
        _: u32,
    ) callconv(.c) void {}
}.f;

fn setProperty(
    comptime T: type,
    comptime field_name: [:0]const u8,
    instance: *T,
    variant: *const builtins.Variant,
) bool {
    const Value = comptime property.PropertyValueType(@FieldType(T, field_name));
    const set = comptime property.setterFn(T, field_name) orelse return false; // .read_only
    const value = variant.asDeclared(Value) orelse return false;
    set(instance, value);
    return true;
}

fn getProperty(
    comptime T: type,
    comptime field_name: [:0]const u8,
    instance: *T,
    r_ret: interface.VariantPtr,
) bool {
    const Value = comptime property.PropertyValueType(@FieldType(T, field_name));
    const getter = comptime property.getterFn(T, field_name);
    const result: *builtins.Variant = @ptrCast(@alignCast(r_ret orelse return false));
    result.* = builtins.Variant.initDeclared(Value, getter(instance));
    return true;
}

fn ListStorage(comptime T: type) type {
    const visible = visibleDescriptorIndices(T);
    return struct {
        var names: [visible.len]builtins.StringName = undefined;
        var class_names: [visible.len]builtins.StringName = undefined;
        var hint_strings: [visible.len]builtins.String = undefined;
        var infos: [visible.len]interface.PropertyInfo = undefined;
        var initialized: bool = false;
    };
}

fn initList(comptime T: type) void {
    const Storage = ListStorage(T);
    const descs = comptime property.descriptors(T);
    const visible = comptime visibleDescriptorIndices(T);

    inline for (visible, 0..) |desc_index, slot| {
        const desc = descs[desc_index];
        Storage.names[slot] = builtins.StringName.fromComptimeLatin1(desc.godot_name);
        Storage.class_names[slot] = builtins.StringName.fromComptimeLatin1(comptime reflect.classNameOf(desc.value_type));
        Storage.hint_strings[slot] = builtins.String.fromComptimeLatin1(desc.hint_string);
        Storage.infos[slot] = .{
            .type = requiredVariantType(T, desc),
            .name = @as(interface.StringNamePtr, @ptrCast(&Storage.names[slot])),
            .class_name = @as(interface.StringNamePtr, @ptrCast(&Storage.class_names[slot])),
            .hint = @backingInt(desc.hint),
            .hint_string = @as(interface.StringPtr, @ptrCast(&Storage.hint_strings[slot])),
            .usage = property.usageBits(desc.usage),
        };
    }
}

/// Variant type for a property value, or a compile error when unsupported.
fn requiredVariantType(
    comptime T: type,
    comptime desc: property.PropertyDescriptor,
) interface.VariantType {
    if (desc.type) |variant_type| return variant_type;
    return comptime builtins.Variant.typeFor(desc.value_type) orelse @compileError(std.fmt.comptimePrint(
        "Property '{s}.{s}' has no Variant type for declared type '{s}'. " ++
            "Supported types are scalars, enums, packed bitfields, codegen builtins, " ++
            "and engine/extension object class pointers. " ++
            "Use '.type' to provide an explicit Variant type override.",
        .{ @typeName(T), desc.field_name, @typeName(desc.value_type) },
    ));
}

const VariantOverrideOwner = struct {
    value: property.Property(u32, .{ .usage = .none, .type = .string }) = .init(0),
    automatic: property.Property(u32, .{ .usage = .none }) = .init(0),
};

/// Descriptor indices exposed in `get_property_list`, in order.
fn visibleDescriptorIndices(comptime T: type) []const usize {
    comptime {
        const descs = property.descriptors(T);
        var indices: [descs.len]usize = undefined;
        var count: usize = 0;
        for (descs, 0..) |desc, i| {
            if (property.usageBits(desc.usage) != 0) {
                indices[count] = i;
                count += 1;
            }
        }
        const out = indices[0..count].*;
        return &out;
    }
}

// Compile-only coverage; analyzed on every build.
//
// The runtime calls below are analyzed, never executed: the engine must be
// initialized before StringName construction.

const Mode = enum(u32) {
    idle = 0,
    running = 1,
};

const Flags = bitpack struct(u32) {
    enabled: bool = false,
    visible: bool = false,
    padding0: u30 = 0,
};

// The fixture classes below are compile-only: they are never registered or
// instantiated. Owned fields (String, StringName, object pointers) are
// initialized with `undefined` only so the annotation-layer default setter
// ownership paths and the opt-in `annotations.deinitPropertyFields` cleanup are
// analyzed; those values are never read or released at runtime.

/// Extension class over an engine `RefCounted` base: opt-in class cleanup must
/// release the owned builtin field of a refcounted extension class.
const TestRefCounted = struct {
    pub const Extends = classes.core.RefCounted;
    base: annotations.Base(Extends) = .{},
    name: property.Property(builtins.StringName, .{ .usage = .none }) = .init(undefined),
};

/// Covers every supported descriptor shape on a real engine base.
const TestNode = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},

    // Usage presets, hints, and every supported value-type family.
    health: property.Property(i32, .{
        .usage = .exported,
        .hint = .range,
        .hint_string = "0,100",
    }) = .init(100),
    speed: property.Property(f32, .{ .usage = .default }) = .init(1),
    hidden: property.Property(u32, .{ .usage = .none }) = .init(0),
    position: property.Property(builtins.Vector2, .{ .usage = .exported }) = .init(.zero),
    alias: property.Property(u32, .{ .usage = .exported, .name = "HealthBar" }) = .init(0),
    label: property.Property(builtins.String, .{ .usage = .exported }) = .init(undefined),
    tag: property.Property(builtins.StringName, .{ .usage = .default }) = .init(undefined),
    mode: property.Property(Mode, .{ .usage = .exported }) = .init(.idle),
    flags: property.Property(Flags, .{ .usage = .exported }) = .init(.{}),
    target: property.Property(?*classes.core.Node, .{ .usage = .exported }) = .init(null),
    resource: property.Property(?*classes.core.Resource, .{ .usage = .exported }) = .init(null),
    owner_node: property.Property(*const classes.core.Node, .{ .usage = .none }) = .init(undefined),
    optional_ref: property.Property(?*const classes.core.RefCounted, .{ .usage = .none }) = .init(null),
    extension_ref: property.Property(*TestRefCounted, .{ .usage = .none }) = .init(undefined),

    // Accessor variants.
    cur: property.Property(i32, .{
        .usage = .exported,
        .get = getCur,
        .set = setCur,
    }) = .init(0),
    ratio: property.Property(f32, .{
        .usage = .default,
        .get = getRatio,
    }) = .init(1),
    pending: property.Property(u32, .{ .usage = .none, .set = setPending }) = .init(0),

    // Custom `.deinit` cleanup hook: honored by the opt-in
    // `annotations.deinitPropertyFields` call in the free-instance path,
    // independently of the default-setter ownership policy.
    hooked: property.Property(builtins.StringName, .{
        .usage = .none,
        .deinit = deinitHooked,
    }) = .init(undefined),

    fn getCur(self: *@This()) i32 {
        return self.cur.value;
    }

    fn setCur(self: *@This(), value: i32) void {
        self.cur.value = value;
    }

    fn getRatio(self: *const @This()) f32 {
        return self.ratio.value;
    }

    fn setPending(self: *@This(), value: u32) void {
        self.pending.value = value;
    }

    fn deinitHooked(self: *@This()) void {
        self.hooked.value.deinit();
    }
};

/// A class whose only property is hidden: set/get are installed, the list is not.
const HiddenOnly = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    secret: property.Property(u32, .{ .usage = .none }) = .init(0),
};

const NoProperties = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    value: u32 = 0,
};

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("registration.property: " ++ message);
}

fn checkDescriptor(
    comptime T: type,
    comptime desc: property.PropertyDescriptor,
    comptime field_name: []const u8,
    comptime godot_name: []const u8,
    comptime expected_type: interface.VariantType,
) void {
    check(std.mem.eql(u8, desc.field_name, field_name), "unexpected property field name for '" ++ field_name ++ "'");
    check(std.mem.eql(u8, desc.godot_name, godot_name), "unexpected engine property name for '" ++ field_name ++ "'");
    check(
        requiredVariantType(T, desc) == expected_type,
        "unexpected Variant type for property '" ++ field_name ++ "'",
    );
}

fn comptimeChecks() void {
    @setEvalBranchQuota(500_000);

    check(hasPropertyFields(TestNode), "a class with Property fields must report them");
    check(hasPropertyFields(HiddenOnly), "a class with only hidden Property fields still declares properties");
    check(!hasPropertyFields(NoProperties), "a class without Property fields must report none");
    check(visiblePropertyCount(TestNode) == 12, "only usage != 0 descriptors belong to get_property_list");
    check(visiblePropertyCount(HiddenOnly) == 0, "a class with only zero-usage properties exposes no list");
    check(visiblePropertyCount(NoProperties) == 0, "a class without Property fields exposes no list");

    // Descriptor table built once: each `Property` wrapper construction runs
    // option normalization at comptime, and repeating it per check would blow
    // the branch quota for larger fixture classes.
    const descs = comptime property.descriptors(TestNode);
    checkDescriptor(TestNode, descs[0], "health", "health", .int);
    checkDescriptor(TestNode, descs[1], "speed", "speed", .float);
    checkDescriptor(TestNode, descs[2], "hidden", "hidden", .int);
    checkDescriptor(TestNode, descs[3], "position", "position", .vector2);
    checkDescriptor(TestNode, descs[4], "alias", "HealthBar", .int);
    checkDescriptor(TestNode, descs[5], "label", "label", .string);
    checkDescriptor(TestNode, descs[6], "tag", "tag", .string_name);
    checkDescriptor(TestNode, descs[7], "mode", "mode", .int);
    checkDescriptor(TestNode, descs[8], "flags", "flags", .int);
    checkDescriptor(TestNode, descs[9], "target", "target", .object);
    checkDescriptor(TestNode, descs[10], "resource", "resource", .object);
    checkDescriptor(TestNode, descs[11], "owner_node", "owner_node", .object);
    checkDescriptor(TestNode, descs[12], "optional_ref", "optional_ref", .object);
    checkDescriptor(TestNode, descs[13], "extension_ref", "extension_ref", .object);
    checkDescriptor(TestNode, descs[14], "cur", "cur", .int);
    checkDescriptor(TestNode, descs[15], "ratio", "ratio", .float);
    checkDescriptor(TestNode, descs[16], "pending", "pending", .int);
    checkDescriptor(TestNode, descs[17], "hooked", "hooked", .string_name);

    check(std.mem.eql(u8, reflect.classNameOf(?*classes.core.Node), "Node"), "engine Node property class name");
    check(std.mem.eql(u8, reflect.classNameOf(?*classes.core.Resource), "Resource"), "engine Resource property class name");
    check(std.mem.eql(u8, reflect.classNameOf(*TestRefCounted), "TestRefCounted"), "extension property class name");
    check(reflect.classNameOf(f32).len == 0, "non-object properties have an empty class name");

    const overrides = property.descriptors(VariantOverrideOwner);
    check(overrides[0].type == .string, ".type override must be preserved");
    check(overrides[1].type == null, "automatic Variant type must stay null");
    check(requiredVariantType(VariantOverrideOwner, overrides[0]) == .string, "type override must win");
    check(requiredVariantType(VariantOverrideOwner, overrides[1]) == .int, "automatic Variant type must fall back to typeFor");

    // Default-setter ownership classification. The policy itself is owned by the
    // annotation layer: known managed builtins are deinitialized and reassigned,
    // `RefCounted` pointers are retained/released, everything else is assigned
    // as-is.
    check(annotations.isKnownManagedBuiltin(builtins.String), "String is a managed builtin for the default setter");
    check(annotations.isKnownManagedBuiltin(builtins.StringName), "StringName is a managed builtin for the default setter");
    check(annotations.isKnownManagedBuiltin(builtins.PackedStringArray), "packed arrays are managed builtins for the default setter");
    check(!annotations.isKnownManagedBuiltin(builtins.Vector2), "plain value builtins are assigned by value");
    check(!annotations.isKnownManagedBuiltin(builtins.Variant), "Variant is assigned by value");
    check(!annotations.isKnownManagedBuiltin(i32), "scalars are assigned by value");
    check(reflect.isRefCountedPointer(?*classes.core.Resource), "Resource pointers are refcounted");
    check(reflect.isRefCountedPointer(*TestRefCounted), "extension RefCounted pointers are refcounted");
    check(reflect.isRefCountedPointer(?*const classes.core.RefCounted), "optional const RefCounted pointers are refcounted");
    check(!reflect.isRefCountedPointer(?*classes.core.Node), "Node pointers are not refcounted and are assigned as-is");

    // Custom `.deinit` hooks come from the annotation layer; the opt-in
    // free-instance cleanup resolves and calls them.
    check(annotations.hasCustomDeinit(@FieldType(TestNode, "hooked")), "custom .deinit must be discoverable on a registration fixture");
    check(!annotations.hasCustomDeinit(@FieldType(TestNode, "label")), "fields without .deinit report no hook");
    check(annotations.deinitFn(TestNode, "hooked") != null, "custom .deinit must resolve to a callable hook");
    check(annotations.deinitFn(TestNode, "label") == null, "fields without .deinit expose no hook");

    // `requiredVariantType` runs for every descriptor from `callbacks`, not only
    // for `get_property_list` entries, so a hidden `Property(Variant, .{ ... })`
    // field is a compile error too. These fixture classes use supported types;
    // an unsupported hidden type is a negative compile check that cannot be
    // analyzed here. `Variant.typeFor(Variant) == null` states the underlying
    // reason.
    validateDescriptors(TestNode);
    validateDescriptors(HiddenOnly);
    check(builtins.Variant.typeFor(builtins.Variant) == null, "Variant must remain an unsupported property value type");
}

fn checkRuntimePaths() void {
    _ = callbacks(TestNode);
    _ = callbacks(TestRefCounted);
    _ = callbacks(HiddenOnly);
    _ = callbacks(NoProperties);
    _ = propertyInfoList(TestNode);
    _ = propertyInfoList(HiddenOnly);

    // Runtime class validation for engine object targets (`asDeclared`): the
    // Variant values are never read because this function is never called.
    var variant: builtins.Variant = undefined;
    _ = variant.asDeclared(?*classes.core.Node);
    _ = variant.asDeclared(*const classes.core.Node);
    _ = variant.asDeclared(?*const classes.core.RefCounted);
    _ = variant.asDeclared(*TestRefCounted);

    // Annotation-layer default setter ownership branches: known managed
    // builtin, `RefCounted` object pointer, and plain assignment for a borrowed
    // non-RefCounted object pointer. The fixture instances are `undefined` on
    // purpose: this function is never called.
    property.setterFn(TestNode, "label").?(@as(*TestNode, undefined), @as(builtins.String, undefined));
    property.setterFn(TestNode, "tag").?(@as(*TestNode, undefined), @as(builtins.StringName, undefined));
    property.setterFn(TestNode, "resource").?(@as(*TestNode, undefined), @as(?*classes.core.Resource, null));
    property.setterFn(TestNode, "optional_ref").?(@as(*TestNode, undefined), @as(?*const classes.core.RefCounted, null));
    property.setterFn(TestNode, "extension_ref").?(@as(*TestNode, undefined), @as(*TestRefCounted, undefined));
    property.setterFn(TestNode, "target").?(@as(*TestNode, undefined), @as(?*classes.core.Node, null));
    property.setterFn(TestNode, "position").?(@as(*TestNode, undefined), builtins.Vector2.zero);
    property.setterFn(TestNode, "health").?(@as(*TestNode, undefined), 0);

    // Opt-in class cleanup (`ClassOptions.auto_property_cleanup`): the
    // free-instance callback runs this helper for the class. It observes the
    // custom `.deinit` hook, owned builtins, and `RefCounted` references.
    annotations.deinitPropertyFields(TestNode, @as(*TestNode, undefined));
    annotations.deinitPropertyFields(TestRefCounted, @as(*TestRefCounted, undefined));
}

comptime {
    comptimeChecks();
    _ = &checkRuntimePaths;
}

/// Runs this module's compile-only checks.
pub fn comptimeSelfCheck() void {
    comptime comptimeChecks();
    _ = &checkRuntimePaths;
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const builtins = @import("../builtins/builtins.zig");

const classes = @import("../classes/classes.zig");

const reflect = @import("../reflect/reflect.zig");

const annotations = @import("../annotations/annotations.zig");

const property = @import("../annotations/property.zig");
