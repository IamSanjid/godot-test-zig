//! Compile-only coverage for the dynamic property backend, moved from
//! `registration/property.zig`: descriptor validation, the set/get/list
//! callbacks, and the `PropertyGroups` layout.
//!
//! The runtime property paths below are analyzed, never executed: the engine
//! must be initialized before `StringName`/`String` construction.

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
// initialized with `undefined` only so the best-effort setter ownership paths
// and the opt-in `annotations.deinitPropertyFields` cleanup are analyzed; those
// values are never read or released at runtime.

/// Extension class over an engine `RefCounted` base: opt-in class cleanup must
/// release the owned builtin field of a refcounted extension class.
const TestRefCounted = struct {
    pub const Extends = classes.core.RefCounted;
    base: annotations.Base(Extends) = .{},
    name: annotations.Property(builtins.StringName, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
};

/// Covers every supported descriptor shape on a real engine base.
const TestNode = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},

    // Usage presets, hints, and every supported value-type family.
    health: annotations.Property(i32, .{
        .usage = .exported,
        .hint = .range,
        .hint_string = "0,100",
    }) = .init(100),
    speed: annotations.Property(f32, .{ .usage = .default }) = .init(1),
    hidden: annotations.Property(u32, .{ .usage = .none }) = .init(0),
    position: annotations.Property(builtins.Vector2, .{ .usage = .exported }) = .init(.zero),
    alias: annotations.Property(u32, .{ .usage = .exported, .name = "HealthBar" }) = .init(0),
    label: annotations.Property(builtins.String, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
    tag: annotations.Property(builtins.StringName, .{
        .usage = .default,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
    mode: annotations.Property(Mode, .{ .usage = .exported }) = .init(.idle),
    flags: annotations.Property(Flags, .{ .usage = .exported }) = .init(.{}),
    target: annotations.Property(?*classes.core.Node, .{ .usage = .exported }) = .init(null),
    resource: annotations.Property(?*classes.core.Resource, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    owner_node: annotations.Property(*const classes.core.Node, .{ .usage = .none }) = .init(undefined),
    optional_ref: annotations.Property(?*const classes.core.RefCounted, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    extension_ref: annotations.Property(*TestRefCounted, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),

    // Accessor variants.
    cur: annotations.Property(i32, .{
        .usage = .exported,
        .get = getCur,
        .set = setCur,
    }) = .init(0),
    ratio: annotations.Property(f32, .{
        .usage = .default,
        .get = getRatio,
    }) = .init(1),
    pending: annotations.Property(u32, .{ .usage = .none, .set = setPending }) = .init(0),

    // Custom `.deinit` cleanup hook: honored by the opt-in
    // `annotations.deinitPropertyFields` call in the free-instance path,
    // independently of the best-effort setter ownership policy.
    hooked: annotations.Property(builtins.StringName, .{
        .usage = .none,
        .set = .best_effort,
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
    secret: annotations.Property(u32, .{ .usage = .none }) = .init(0),
};

// `PropertyGroups` fixture: the list interleaves two section headers with two
// visible fields, in marker order. The hidden field is absent from the layout
// but still validated. Compile-only, like the other fixtures below.
const TestGrouped = struct {
    pub const Extends = classes.core.Node;
    pub const Groups = annotations.PropertyGroups(.{
        .{
            .name = "Combat",
            .fields = .{"health"},
            .groups = .{
                .{ .name = "Vitals", .fields = .{"stamina"} },
            },
        },
    });

    base: annotations.Base(Extends) = .{},
    health: annotations.Property(i32, .{ .usage = .exported }) = .init(100),
    stamina: annotations.Property(f32, .{ .usage = .exported }) = .init(50),
    secret: annotations.Property(u32, .{ .usage = .none }) = .init(0),
};

const NoProperties = struct {
    pub const Extends = classes.core.Node;
    base: annotations.Base(Extends) = .{},
    value: u32 = 0,
};

const VariantOverrideOwner = struct {
    value: annotations.Property(u32, .{ .usage = .none, .type = .string }) = .init(0),
    automatic: annotations.Property(u32, .{ .usage = .none }) = .init(0),
};

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("registration property tests: " ++ message);
}

/// Public equivalent of the backend's private `requiredVariantType`: an explicit
/// `.type` override wins, otherwise the declared value type is mapped through
/// `conversion.variantType`.
fn effectiveVariantType(comptime desc: annotations.property.PropertyDescriptor) interface.VariantType {
    if (desc.type) |variant_type| return variant_type;
    return godot.conversion.variantType(desc.value_type) orelse
        @compileError(std.fmt.comptimePrint(
            "Property '{s}' has no Variant type for declared type '{s}'.",
            .{ desc.field_name, @typeName(desc.value_type) },
        ));
}

fn visibleDescriptorCount(comptime T: type) usize {
    var count: usize = 0;
    for (annotations.property.descriptors(T)) |desc| {
        if (annotations.property.usageBits(desc.usage) != 0) count += 1;
    }
    return count;
}

fn checkDescriptor(
    comptime desc: annotations.property.PropertyDescriptor,
    comptime field_name: []const u8,
    comptime godot_name: []const u8,
    comptime expected_type: interface.VariantType,
) void {
    check(std.mem.eql(u8, desc.field_name, field_name), "unexpected property field name for '" ++ field_name ++ "'");
    check(std.mem.eql(u8, desc.godot_name, godot_name), "unexpected engine property name for '" ++ field_name ++ "'");
    check(
        effectiveVariantType(desc) == expected_type,
        "unexpected Variant type for property '" ++ field_name ++ "'",
    );
}

fn checkDescriptors() void {
    @setEvalBranchQuota(500_000);

    check(registration_property.hasPropertyFields(TestNode), "a class with Property fields must report them");
    check(registration_property.hasPropertyFields(HiddenOnly), "a class with only hidden Property fields still declares properties");
    check(!registration_property.hasPropertyFields(NoProperties), "a class without Property fields must report none");
    check(registration_property.propertyEntryCount(TestNode) == 12, "only usage != 0 descriptors belong to get_property_list");
    check(
        registration_property.propertyEntryCount(TestNode) == visibleDescriptorCount(TestNode),
        "a class without PropertyGroups lists its visible fields only",
    );
    check(registration_property.propertyEntryCount(HiddenOnly) == 0, "a class with only zero-usage properties exposes no list");
    check(registration_property.propertyEntryCount(NoProperties) == 0, "a class without Property fields exposes no list");
    check(registration_property.propertyEntryCount(TestGrouped) == 4, "section headers count as list entries");
    check(visibleDescriptorCount(TestGrouped) == 2, "only visible fields become field entries");
    check(
        registration_property.propertyEntryCount(TestGrouped) - visibleDescriptorCount(TestGrouped) == 2,
        "each PropertyGroups section header counts as one list entry",
    );
    // The backend's `sectionHintString`/`sectionUsage` helpers are private, and
    // the annotation-layer `layout`/`Section` only describe section names and
    // depths, so the exact header hint/usage mapping is only analyzed (through
    // `propertyInfoList`), not asserted here. The entry-count split above is the
    // public equivalent.

    // Descriptor table built once: each `Property` wrapper construction runs
    // option normalization at comptime, and repeating it per check would blow
    // the branch quota for larger fixture classes.
    const descs = comptime annotations.property.descriptors(TestNode);
    checkDescriptor(descs[0], "health", "health", .int);
    checkDescriptor(descs[1], "speed", "speed", .float);
    checkDescriptor(descs[2], "hidden", "hidden", .int);
    checkDescriptor(descs[3], "position", "position", .vector2);
    checkDescriptor(descs[4], "alias", "HealthBar", .int);
    checkDescriptor(descs[5], "label", "label", .string);
    checkDescriptor(descs[6], "tag", "tag", .string_name);
    checkDescriptor(descs[7], "mode", "mode", .int);
    checkDescriptor(descs[8], "flags", "flags", .int);
    checkDescriptor(descs[9], "target", "target", .object);
    checkDescriptor(descs[10], "resource", "resource", .object);
    checkDescriptor(descs[11], "owner_node", "owner_node", .object);
    checkDescriptor(descs[12], "optional_ref", "optional_ref", .object);
    checkDescriptor(descs[13], "extension_ref", "extension_ref", .object);
    checkDescriptor(descs[14], "cur", "cur", .int);
    checkDescriptor(descs[15], "ratio", "ratio", .float);
    checkDescriptor(descs[16], "pending", "pending", .int);
    checkDescriptor(descs[17], "hooked", "hooked", .string_name);

    check(std.mem.eql(u8, reflect.classNameOf(?*classes.core.Node), "Node"), "engine Node property class name");
    check(std.mem.eql(u8, reflect.classNameOf(?*classes.core.Resource), "Resource"), "engine Resource property class name");
    check(std.mem.eql(u8, reflect.classNameOf(*TestRefCounted), "TestRefCounted"), "extension property class name");
    check(reflect.classNameOf(f32).len == 0, "non-object properties have an empty class name");

    const overrides = annotations.property.descriptors(VariantOverrideOwner);
    check(overrides[0].type == .string, ".type override must be preserved");
    check(overrides[1].type == null, "automatic Variant type must stay null");
    check(effectiveVariantType(overrides[0]) == .string, "type override must win");
    check(effectiveVariantType(overrides[1]) == .int, "automatic Variant type must fall back to typeFor");
}

fn checkLifetime() void {
    @setEvalBranchQuota(500_000);

    // Best-effort ownership classification. The policy itself is owned by the
    // annotation layer: known managed builtins are deinitialized and reassigned,
    // `RefCounted` pointers are retained/released, everything else is assigned
    // as-is.
    check(builtins.isManaged(builtins.String), "String is a managed builtin for the best-effort setter");
    check(builtins.isManaged(builtins.StringName), "StringName is a managed builtin for the best-effort setter");
    check(builtins.isManaged(builtins.PackedStringArray), "packed arrays are managed builtins for the best-effort setter");
    check(!builtins.isManaged(builtins.Vector2), "plain value builtins are assigned by value");
    check(!builtins.isManaged(builtins.Variant), "Variant is assigned by value");
    check(!builtins.isManaged(i32), "scalars are assigned by value");
    check(reflect.isRefCountedPointer(?*classes.core.Resource), "Resource pointers are refcounted");
    check(reflect.isRefCountedPointer(*TestRefCounted), "extension RefCounted pointers are refcounted");
    check(reflect.isRefCountedPointer(?*const classes.core.RefCounted), "optional const RefCounted pointers are refcounted");
    check(!reflect.isRefCountedPointer(?*classes.core.Node), "Node pointers are not refcounted and are assigned as-is");

    // Custom `.deinit` hooks come from the annotation layer; the opt-in
    // free-instance cleanup resolves and calls them. `.best_effort` is not a
    // custom hook.
    check(annotations.property.hasCustomDeinit(@FieldType(TestNode, "hooked")), "custom .deinit must be discoverable on a registration fixture");
    check(!annotations.property.hasCustomDeinit(@FieldType(TestNode, "label")), "best-effort cleanup reports no custom hook");
    check(annotations.property.deinitFn(TestNode, "hooked") != null, "custom .deinit must resolve to a callable hook");
    check(annotations.property.deinitFn(TestNode, "label") == null, "best-effort cleanup exposes no custom hook");

    // Descriptor validation runs for every descriptor from `callbacks`, not only
    // for `get_property_list` entries, so a hidden `Property(Variant, .{ ... })`
    // field is a compile error too. These fixture classes use supported types;
    // an unsupported hidden type is a negative compile check that cannot be
    // analyzed here. `Variant.typeFor(Variant) == null` states the underlying
    // reason.
    check(builtins.Variant.typeFor(builtins.Variant) == null, "Variant must remain an unsupported property value type");
}

fn checkRuntimePaths() void {
    _ = registration_property.callbacks(TestNode);
    _ = registration_property.callbacks(TestRefCounted);
    _ = registration_property.callbacks(HiddenOnly);
    _ = registration_property.callbacks(NoProperties);
    _ = registration_property.callbacks(TestGrouped);
    _ = registration_property.propertyInfoList(TestNode);
    _ = registration_property.propertyInfoList(HiddenOnly);
    // Forces analysis of the section branch in `initList`; never executes the
    // engine StringName/String constructors.
    _ = registration_property.propertyInfoList(TestGrouped);

    // Runtime class validation for engine object targets (`asDeclared`): the
    // Variant values are never read because this function is never called.
    var variant: builtins.Variant = undefined;
    _ = variant.asDeclared(?*classes.core.Node);
    _ = variant.asDeclared(*const classes.core.Node);
    _ = variant.asDeclared(?*const classes.core.RefCounted);
    _ = variant.asDeclared(*TestRefCounted);

    // Best-effort setter ownership branches: known managed builtin, `RefCounted`
    // object pointer, and plain assignment for a borrowed non-RefCounted object
    // pointer. The fixture instances are `undefined` on purpose: this function
    // is never called.
    annotations.property.setterFn(TestNode, "label").?(@as(*TestNode, undefined), @as(builtins.String, undefined));
    annotations.property.setterFn(TestNode, "tag").?(@as(*TestNode, undefined), @as(builtins.StringName, undefined));
    annotations.property.setterFn(TestNode, "resource").?(@as(*TestNode, undefined), @as(?*classes.core.Resource, null));
    annotations.property.setterFn(TestNode, "optional_ref").?(@as(*TestNode, undefined), @as(?*const classes.core.RefCounted, null));
    annotations.property.setterFn(TestNode, "extension_ref").?(@as(*TestNode, undefined), @as(*TestRefCounted, undefined));
    annotations.property.setterFn(TestNode, "target").?(@as(*TestNode, undefined), @as(?*classes.core.Node, null));
    annotations.property.setterFn(TestNode, "position").?(@as(*TestNode, undefined), builtins.Vector2.zero);
    annotations.property.setterFn(TestNode, "health").?(@as(*TestNode, undefined), 0);

    // Opt-in class cleanup (`ClassOptions.auto_property_cleanup`): the
    // free-instance callback runs this helper for the class. It observes the
    // custom `.deinit` hook, owned builtins, and `RefCounted` references.
    annotations.deinitPropertyFields(TestNode, @as(*TestNode, undefined));
    annotations.deinitPropertyFields(TestRefCounted, @as(*TestRefCounted, undefined));
}

test "property descriptors and get_property_list entry counts" {
    comptime checkDescriptors();
}

test "Variant type overrides and ownership classification" {
    comptime checkLifetime();
}

test "runtime property callbacks analyze without engine calls" {
    _ = &checkRuntimePaths;
}

const std = @import("std");

const godot = @import("godot");
const annotations = godot.annotations;
const builtins = godot.builtins;
const classes = godot.classes;
const enums = godot.enums;
const interface = godot.bindings.interface;
const reflect = godot.reflect;
const registration_property = godot.registration.property;
