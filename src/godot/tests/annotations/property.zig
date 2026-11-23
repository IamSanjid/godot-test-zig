//! `Property` / `PropertyGroups` options, discovery, descriptors, accessors,
//! lifetime, layout, and type-derived hints.
//!
//! These checks are compile-only: the functions below run from `comptime`
//! blocks or are referenced for semantic analysis.
//!
//! A duplicate engine name is a compile error and therefore cannot be exercised
//! here; `descriptors` reports it with both conflicting field names. The
//! `.read_only = true` + custom `.set` conflict and malformed `.init`
//! initializers (not an `Init` type, or a mismatched `InitFor`) are compile
//! errors for the same reason; `normalizeOptions` reports them.

fn usageBits(flags: godot.enums.PropertyUsageFlags) u32 {
    return @bitCast(flags);
}

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("property tests: " ++ message);
}

const UsageOwner = struct {
    from_literal: godot.annotations.Property(u32, .{ .usage = .none }) = .init(0),
    from_flags: godot.annotations.Property(u32, .{ .usage = .{ .storage = true } }) = .init(0),
    from_value: godot.annotations.Property(u32, .{ .usage = .default }) = .init(0),
};

const VariantTypeOwner = struct {
    literal: godot.annotations.Property(u32, .{ .usage = .none, .type = .string }) = .init(0),
    explicit: godot.annotations.Property(f32, .{ .usage = .none, .type = godot.bindings.interface.VariantType.float }) = .init(0),
    automatic: godot.annotations.Property(u32, .{ .usage = .none }) = .init(0),
};

const CheckOwner = struct {
    plain: u32 = 0,
    count: godot.annotations.Property(u32, .{ .usage = .none }) = .init(0),
    health: godot.annotations.Property(i32, .{
        .usage = .{ .storage = true, .editor = true },
        .hint = .range,
        .hint_string = "0,100",
        .name = "Health",
        .get = getHealth,
        .set = setHealth,
    }) = .init(100),
    ratio: godot.annotations.Property(f32, .{
        .usage = .default,
        .get = getRatio,
    }) = .init(1.0),
    tag: godot.annotations.Property(u32, .{ .usage = .{ .storage = true } }) = .init(0),

    fn getHealth(self: *@This()) i32 {
        return self.health.value;
    }

    fn setHealth(self: *@This(), value: i32) void {
        self.health.value = value;
    }

    fn getRatio(self: *const @This()) f32 {
        return self.ratio.value;
    }
};

const NamingOwner = struct {
    healthBar: godot.annotations.Property(u32, .{ .usage = .exported }) = .init(0),
};

/// A custom setter without a getter keeps the default getter.
const SetterOnlyOwner = struct {
    value: godot.annotations.Property(u32, .{ .usage = .none, .set = set }) = .init(1),

    fn set(self: *@This(), stored: u32) void {
        self.value.value = stored + 1;
    }
};

/// `.read_only` rejects engine sets but does not change usage flags.
const ReadOnlyOwner = struct {
    sealed: godot.annotations.Property(u32, .{
        .usage = .exported,
        .read_only = true,
    }) = .init(9),
    computed: godot.annotations.Property(f32, .{
        .usage = .none,
        .read_only = true,
        .get = getComputed,
    }) = .init(1.5),
    writable: godot.annotations.Property(u32, .{
        .usage = .none,
        .read_only = false,
        .set = setWritable,
    }) = .init(0),

    fn getComputed(self: *const @This()) f32 {
        return self.computed.value;
    }

    fn setWritable(self: *@This(), value: u32) void {
        self.writable.value = value;
    }
};

const NoProperties = struct {
    value: u32 = 0,
};

/// Lookalike marker: discovery must ignore it.
const Lookalike = struct {
    value: u32 = 0,

    pub fn isSelf(OtherT: type) bool {
        return OtherT == Lookalike;
    }
};

/// Mixed annotation kinds must not cross-classify fields.
const MixedOwner = struct {
    node: godot.annotations.OnReady(godot.classes.core.Node).Node("./ChildNode"),
    lookalike: Lookalike = .{},
    health: godot.annotations.Property(i32, .{ .usage = .exported }) = .init(0),
};

/// Same `groups` payload shape as a real marker, but no marker kind.
const PropertyGroupsLookalike = struct {
    pub const Groups = struct {
        pub const groups = .{
            .{ .name = "Nope", .fields = .{"value"} },
        };
    };
};

/// Holder-owned user value type.
const DeinitProbe = struct {
    deinit_called: bool = false,
    hook_called: bool = false,

    pub fn deinit(self: *@This()) void {
        self.deinit_called = true;
    }
};

/// Custom `.deinit` overrides the best-effort cleanup.
const HookOwner = struct {
    probe: godot.annotations.Property(DeinitProbe, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = deinitProbe,
    }) = .init(.{}),
    plain: godot.annotations.Property(u32, .{
        .usage = .none,
        .deinit = deinitPlain,
    }) = .init(0),
    plain_deinit_called: bool = false,

    fn deinitProbe(self: *@This()) void {
        self.probe.value.hook_called = true;
    }

    fn deinitPlain(self: *@This()) void {
        self.plain_deinit_called = true;
    }
};

/// Best-effort cleanup applies even with custom accessors.
const FieldLifetimeOwner = struct {
    plain: godot.annotations.Property(u32, .{ .usage = .none }) = .init(0),
    probe: godot.annotations.Property(DeinitProbe, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(.{}),
    accessor: godot.annotations.Property(DeinitProbe, .{
        .usage = .none,
        .get = getAccessor,
        .set = setAccessor,
        .deinit = .best_effort,
    }) = .init(.{}),

    fn getAccessor(self: *const @This()) DeinitProbe {
        return self.accessor.value;
    }

    fn setAccessor(self: *@This(), value: DeinitProbe) void {
        self.accessor.value = value;
    }
};

/// `.best_effort` installs the built-in policy but is not a custom hook.
const BestEffortProbeOwner = struct {
    probe: godot.annotations.Property(DeinitProbe, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(.{}),
};

/// Compile-only best-effort engine paths: managed builtin, `Variant`, and a
/// `RefCounted` pointer. The values are never read.
const BestEffortOwner = struct {
    string: godot.annotations.Property(godot.builtins.String, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
    variant: godot.annotations.Property(godot.builtins.Variant, .{
        .usage = .none,
        .type = .string,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(godot.builtins.Variant.nil),
    ref: godot.annotations.Property(?*godot.classes.core.RefCounted, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
};

/// Read-only managed values declare cleanup and no setter.
const ReadOnlyManagedOwner = struct {
    name: godot.annotations.Property(godot.builtins.String, .{
        .usage = .none,
        .read_only = true,
        .deinit = .best_effort,
    }) = .init(undefined),
    locked_ref: godot.annotations.Property(?*godot.classes.core.RefCounted, .{
        .usage = .none,
        .read_only = true,
        .deinit = .best_effort,
    }) = .init(null),
};

/// Extension over `RefCounted`; helpers resolve the engine base.
const RefCountedExtension = struct {
    pub const Extends = godot.classes.core.RefCounted;
    base: godot.annotations.Base(Extends) = .{},
};

/// `.base` placeholder target.
const InitializerBase = struct {
    bonus: u32 = 3,
};

fn initialCount() u32 {
    return 40;
}

fn initialDoubled(seed: u32) u32 {
    return seed * 2;
}

fn initialFromOwner(owner: *InitializerOwner) u32 {
    return owner.seed + 1;
}

fn initialFromBase(base: *InitializerBase) u32 {
    return base.bonus;
}

/// `.init` placeholders: values, fields, owner, and base.
const InitializerOwner = struct {
    seed: u32 = 5,
    plain: godot.annotations.Property(u32, .{ .usage = .none }) = .init(11),
    count: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, initialCount, .{}),
    }) = .init(0),
    doubled: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, initialDoubled, .{.{ .field = "seed" }}),
    }) = .init(0),
    owned: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, initialFromOwner, .{.owner}),
    }) = .init(0),
    based: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, initialFromBase, .{.base}),
    }) = .init(0),
    shorthand: godot.annotations.Property(u32, .{ .usage = .none }).Init(
        initialDoubled,
        .{.{ .field = "seed" }},
    ) = .init(0),
};

/// Compile-only `.init` coverage; engine paths are analyzed, not executed.
const BuiltinInitializerOwner = struct {
    name: godot.annotations.Property(godot.builtins.StringName, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
        .init = godot.annotations.Init(godot.builtins.StringName, .fromLatin1, .{ "probe", false }),
    }) = .init(undefined),
    count: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, initialCount, .{}),
    }) = .init(0),
};

/// Compile-only `Variant` ownership coverage.
const VariantValueOwner = struct {
    value: godot.annotations.Property(godot.builtins.Variant, .{
        .usage = .none,
        .type = .string,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(godot.builtins.Variant.nil),
};

/// Compile-only ownership coverage; engine calls are not executed.
const RefLifetimeOwner = struct {
    engine: godot.annotations.Property(?*godot.classes.core.RefCounted, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    engine_const: godot.annotations.Property(*const godot.classes.core.RefCounted, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
    extension: godot.annotations.Property(?*RefCountedExtension, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    extension_const: godot.annotations.Property(*const RefCountedExtension, .{
        .usage = .none,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),
    node: godot.annotations.Property(?*godot.classes.core.Node, .{ .usage = .none }) = .init(null),
};

fn checkVariantValueProperty() void {
    const set = godot.annotations.property.setterFn(VariantValueOwner, "value") orelse @compileError("Variant value property must have a setter");
    _ = set;
    const desc = godot.annotations.property.descriptors(VariantValueOwner)[0];
    check(desc.type == .string, "Variant value property must use the explicit type override");
}

fn checkUsageNormalization() void {
    check(usageBits(godot.enums.PropertyUsageFlags.none) == 0, ".none must be zero flags");
    check(usageBits(godot.enums.PropertyUsageFlags.default) == 6, ".default must be PROPERTY_USAGE_DEFAULT (storage + editor)");
    check(usageBits(godot.enums.PropertyUsageFlags.exported) == 6, ".exported must be storage + editor");

    const usage_descs = godot.annotations.property.descriptors(UsageOwner);
    check(usageBits(usage_descs[0].usage) == 0, "'.usage = .none' must normalize to zero flags");
    check(usageBits(usage_descs[1].usage) == 2, "anonymous flag structs must normalize into PropertyUsageFlags");
    check(usageBits(usage_descs[2].usage) == 6, "PropertyUsageFlags values must pass through unchanged");
}

fn checkVariantTypeOverride() void {
    const descs = godot.annotations.property.descriptors(VariantTypeOwner);
    check(descs[0].type == .string, ".type enum literal must normalize");
    check(descs[1].type == .float, "interface.VariantType value must pass through");
    check(descs[2].type == null, "omitted .type must stay automatic");
    check(@FieldType(VariantTypeOwner, "literal").variant_type == .string, "wrapper must expose normalized variant_type");
}

fn checkDiscovery() void {
    const names = godot.annotations.property.findPropertyFieldNames(CheckOwner);
    check(names.len == 4, "findPropertyFieldNames must collect only Property fields, in declaration order");
    check(std.mem.eql(u8, names[0], "count"), "findPropertyFieldNames must keep declaration order (1)");
    check(std.mem.eql(u8, names[1], "health"), "findPropertyFieldNames must keep declaration order (2)");
    check(std.mem.eql(u8, names[2], "ratio"), "findPropertyFieldNames must keep declaration order (3)");
    check(std.mem.eql(u8, names[3], "tag"), "findPropertyFieldNames must keep declaration order (4)");

    check(godot.annotations.property.findPropertyFieldNames(NoProperties).len == 0, "classes without Property fields must report no properties");
    check(godot.annotations.property.findPropertyFieldNames(Lookalike).len == 0, "a lookalike isSelf must not be discovered"); // Lookalike itself has no Property field
    check(godot.annotations.property.isPropertyField(@FieldType(CheckOwner, "health")), "Property wrappers must identify themselves");
    check(!godot.annotations.property.isPropertyField(u32), "scalars are not Property wrappers");
    check(!godot.annotations.property.isPropertyField(@FieldType(CheckOwner, "plain")), "plain fields are not Property wrappers");
    check(!godot.annotations.property.isPropertyField(Lookalike), "a lookalike isSelf is not a Property wrapper");
}

fn checkDescriptors() void {
    const descs = godot.annotations.property.descriptors(CheckOwner);
    check(descs.len == 4, "descriptors must cover every discovered field");
    check(std.mem.eql(u8, descs[0].field_name, "count"), "descriptor field_name must be the Zig field name");
    check(descs[0].value_type == u32, "descriptor value_type must be the wrapper PropertyFor");
    check(std.mem.eql(u8, descs[0].godot_name, "count"), "default engine name must come from the field name");
    check(std.mem.eql(u8, descs[1].godot_name, "Health"), "explicit '.name' must be used verbatim");
    check(descs[1].value_type == i32, "descriptor value_type must follow the field");
    check(descs[1].hint == godot.enums.PropertyHint.range, "'.hint = .range' must normalize to PropertyHint.range");
    check(std.mem.eql(u8, descs[1].hint_string, "0,100"), "hint_string must keep the declared bytes");
    check(descs[1].hint_string[descs[1].hint_string.len] == 0, "hint_string must be sentinel-terminated");
    check(usageBits(descs[1].usage) == usageBits(godot.enums.PropertyUsageFlags.exported), "anonymous flag struct must equal the exported preset");
    check(descs[2].hint == .none, "omitted hints default to .none");
    check(descs[2].hint_string.len == 0, "omitted hint strings default to empty");
    check(descs[2].hint_string[0] == 0, "omitted hint strings must still be sentinel-terminated");
    check(usageBits(descs[3].usage) == 2, "single anonymous flag must normalize");

    const naming_descs = godot.annotations.property.descriptors(NamingOwner);
    check(std.mem.eql(u8, naming_descs[0].godot_name, "health_bar"), "default engine names must use naming.comptimeConvert");
}

fn checkAccessors() void {
    const Health = @FieldType(CheckOwner, "health");
    check(godot.annotations.property.hasCustomGetter(Health), "custom .get must be detected");
    check(godot.annotations.property.hasCustomSetter(Health), "custom .set must be detected");
    check(!godot.annotations.property.hasCustomGetter(@FieldType(CheckOwner, "count")), "properties without .get must report no custom getter");
    check(!godot.annotations.property.hasCustomSetter(@FieldType(CheckOwner, "count")), "properties without .set must report no custom setter");
    check(godot.annotations.property.hasCustomGetter(@FieldType(CheckOwner, "ratio")), "const getters must be detected");

    const health_getter = godot.annotations.property.getterFn(CheckOwner, "health");
    const health_setter = godot.annotations.property.setterFn(CheckOwner, "health") orelse @compileError("property tests: custom setter must be discovered");
    check(@TypeOf(health_getter) == fn (*CheckOwner) i32, "custom getter thunk must take a mutable owner pointer");
    check(@TypeOf(health_setter) == fn (*CheckOwner, i32) void, "custom setter thunk must match the accessor shape");
    check(godot.annotations.property.isWritable(CheckOwner, "health"), "custom setter properties are writable");
    check(godot.annotations.property.isWritable(CheckOwner, "count"), "stored-value properties are writable by default");
    check(godot.annotations.property.isWritable(CheckOwner, "ratio"), "custom getters without setters use the default write");
    check(godot.annotations.property.setterFn(CheckOwner, "ratio") != null, "custom getters without setters expose the default setter");
    check(@TypeOf(godot.annotations.property.getterFn(CheckOwner, "ratio")) == fn (*CheckOwner) f32, "const getters must be callable through a mutable owner");
    check(@TypeOf(godot.annotations.property.getterFn(CheckOwner, "count")) == fn (*CheckOwner) u32, "default getters use the owner pointer");

    const setter_only = @FieldType(SetterOnlyOwner, "value");
    check(!godot.annotations.property.hasCustomGetter(setter_only), "setter-only properties keep the default getter");
    check(godot.annotations.property.hasCustomSetter(setter_only), "setter-only properties must report their custom setter");
    check(godot.annotations.property.isWritable(SetterOnlyOwner, "value"), "setter-only properties are writable");
    var setter_only_owner: SetterOnlyOwner = .{};
    check(godot.annotations.property.getterFn(SetterOnlyOwner, "value")(&setter_only_owner) == 1, "setter-only properties read the stored value");
    godot.annotations.property.setterFn(SetterOnlyOwner, "value").?(&setter_only_owner, 41);
    check(godot.annotations.property.getterFn(SetterOnlyOwner, "value")(&setter_only_owner) == 42, "setter-only properties call the custom setter");

    var owner: CheckOwner = .{};
    check(health_getter(&owner) == 100, "default field values must be readable through the accessor");
    health_setter(&owner, 7);
    check(health_getter(&owner) == 7, "custom accessors must see the same stored value");
    godot.annotations.property.setterFn(CheckOwner, "count").?(&owner, 3);
    check(godot.annotations.property.getterFn(CheckOwner, "count")(&owner) == 3, "default setter must write the stored value");
    godot.annotations.property.setterFn(CheckOwner, "ratio").?(&owner, 2.5);
    check(godot.annotations.property.getterFn(CheckOwner, "ratio")(&owner) == 2.5, "default setter must write .value behind a custom getter");

    const Wrapper = godot.annotations.Property(i32, .{ .usage = .exported });
    var wrapper: Wrapper = .init(5);
    check(wrapper.get() == 5, "Property.get must read the stored value");
    wrapper.set(9);
    check(wrapper.get() == 9, "Property.set must write the stored value");
    check(Wrapper.PropertyFor == i32, "PropertyFor must expose the value type");
    check(usageBits(Wrapper.usage) == usageBits(godot.enums.PropertyUsageFlags.exported), "wrapper options must be normalized");
    check(Wrapper.marker == godot.annotations.marker.Kind.property, "Property wrappers must declare marker.Kind.property");
}

fn checkReadOnly() void {
    const sealed = @FieldType(ReadOnlyOwner, "sealed");
    check(sealed.read_only, "read_only must be exposed on the wrapper");
    check(!sealed.has_custom_get, ".read_only must keep the default getter");
    check(!sealed.has_custom_set, ".read_only must not declare a custom setter");
    check(godot.annotations.property.isReadOnly(ReadOnlyOwner, "sealed"), ".read_only properties must reject engine set dispatch");
    check(!godot.annotations.property.isWritable(ReadOnlyOwner, "sealed"), ".read_only properties must not be writable");
    check(godot.annotations.property.setterFn(ReadOnlyOwner, "sealed") == null, ".read_only properties expose no setter");

    var owner: ReadOnlyOwner = .{};
    check(godot.annotations.property.getterFn(ReadOnlyOwner, "sealed")(&owner) == 9, ".read_only properties keep the default getter");
    check(godot.annotations.property.getterFn(ReadOnlyOwner, "computed")(&owner) == 1.5, "read-only properties keep their custom getter");

    check(godot.annotations.property.isReadOnly(ReadOnlyOwner, "computed"), "explicit .read_only must reject the default setter");
    check(godot.annotations.property.setterFn(ReadOnlyOwner, "computed") == null, "explicit .read_only exposes no setter");

    const writable = @FieldType(ReadOnlyOwner, "writable");
    check(!writable.read_only, "read_only must normalize an explicit false");
    check(godot.annotations.property.isWritable(ReadOnlyOwner, "writable"), "explicit read_only = false must keep a custom setter writable");
    godot.annotations.property.setterFn(ReadOnlyOwner, "writable").?(&owner, 4);
    check(owner.writable.value == 4, "explicit read_only = false must dispatch the custom setter");

    // Usage flags are untouched: `.read_only` is dispatch policy, not inspector
    // metadata. The inspector flag stays an explicit usage flag.
    const descs = godot.annotations.property.descriptors(ReadOnlyOwner);
    check(descs.len == 3, "read-only checks must cover every Property field");
    check(usageBits(descs[0].usage) == usageBits(godot.enums.PropertyUsageFlags.exported), ".read_only must not change usage flags");
    const inspector_read_only = usageBits(.{ .read_only = true });
    check((usageBits(descs[0].usage) & inspector_read_only) == 0, ".read_only must not imply PropertyUsageFlags.read_only");
}

fn checkInitializers() void {
    const count = @FieldType(InitializerOwner, "count");
    check(count.has_custom_init, "has_custom_init must mirror the option");
    check(godot.annotations.property.hasCustomInitializer(count), "hasCustomInitializer must detect a declared .init");
    check(!godot.annotations.property.hasCustomInitializer(@FieldType(InitializerOwner, "plain")), "fields without .init must report no custom initializer");
    check(!count.has_custom_get and !count.has_custom_set, ".init is creation-time only and not an engine accessor");

    // Eager creation-time assignment: replace ordinary field defaults with the
    // initializer results, resolving every placeholder form.
    var owner: InitializerOwner = .{};
    var base: InitializerBase = .{};
    godot.annotations.initPropertyFields(InitializerOwner, InitializerBase, &owner, &base);
    check(owner.count.value == 40, ".init initializer results must be assigned eagerly");
    check(owner.doubled.value == 10, ".init 'field' arguments must resolve owner fields");
    check(owner.owned.value == 6, ".init 'owner' arguments must pass the owner pointer");
    check(owner.based.value == 3, ".init 'base' arguments must pass the base pointer");
    check(owner.shorthand.value == 10, ".Init(...) shorthand must add the same eager initializer");
    check(godot.annotations.property.hasCustomInitializer(@FieldType(InitializerOwner, "shorthand")), ".Init(...) shorthand must expose the initializer");
    check(owner.plain.value == 11, "initPropertyFields must leave fields without .init alone");

    var no_props: NoProperties = .{};
    var dummy_base: void = {};
    godot.annotations.initPropertyFields(NoProperties, void, &no_props, &dummy_base);
    check(no_props.value == 0, "initPropertyFields must ignore classes without Property fields");
}

fn checkMarkerIdentity() void {
    check(godot.annotations.marker.is(@FieldType(CheckOwner, "health"), .property), "Property marker kind must be property");
    check(!godot.annotations.marker.is(@FieldType(CheckOwner, "health"), .on_ready), "Property marker must not read as OnReady");
    check(!godot.annotations.marker.is(@FieldType(CheckOwner, "health"), .base), "Property marker must not read as Base");

    check(GroupedOwner.Groups.marker == godot.annotations.marker.Kind.property_groups, "PropertyGroups markers must declare marker.Kind.property_groups");
    check(godot.annotations.marker.is(GroupedOwner.Groups, .property_groups), "PropertyGroups markers must identify as the property_groups family");
    check(godot.annotations.property.findPropertyGroups(GroupedOwner).len == 1, "marker-backed PropertyGroups must be discovered");
    check(godot.annotations.marker.kindOf(PropertyGroupsLookalike.Groups) == null, "a PropertyGroups lookalike must not declare an annotation marker");
    check(godot.annotations.property.findPropertyGroups(PropertyGroupsLookalike).len == 0, "a PropertyGroups lookalike without the marker kind must not be discovered");

    const mixed_props = godot.annotations.property.findPropertyFieldNames(MixedOwner);
    const mixed_on_ready = godot.annotations.findOnReadyFieldNames(MixedOwner);
    check(mixed_props.len == 1, "mixed classes must report exactly their Property fields");
    check(std.mem.eql(u8, mixed_props[0], "health"), "mixed classes must not report OnReady fields as properties");
    check(mixed_on_ready.len == 1, "mixed classes must report exactly their OnReady fields");
    check(std.mem.eql(u8, mixed_on_ready[0], "node"), "mixed classes must not report Property fields as OnReady");
    check(!godot.annotations.property.isPropertyField(@FieldType(MixedOwner, "node")), "OnReady wrappers are not Property fields");
    check(!godot.annotations.marker.is(@FieldType(MixedOwner, "lookalike"), .property), "lookalikes must not declare a marker");
}

fn checkLifetime() void {
    // Custom `.deinit` hooks: detected, callable, and validated through
    // `descriptors` once the owning class is known.
    const hooked = @FieldType(HookOwner, "probe");
    check(godot.annotations.property.hasCustomDeinit(hooked), "custom .deinit must be detected");
    check(hooked.has_custom_deinit, "has_custom_deinit must mirror the option");
    check(!godot.annotations.property.hasCustomDeinit(@FieldType(FieldLifetimeOwner, "probe")), ".best_effort reports no custom deinit");
    const hook_fn = godot.annotations.property.deinitFn(HookOwner, "probe") orelse @compileError("property tests: custom .deinit must be discoverable");
    check(@TypeOf(hook_fn) == fn (*HookOwner) void, "custom .deinit thunk must take a mutable owner pointer");
    check(godot.annotations.property.deinitFn(FieldLifetimeOwner, "probe") == null, ".best_effort exposes no custom deinit hook");
    _ = godot.annotations.property.descriptors(HookOwner);

    // Custom hook overrides the best-effort cleanup.
    var hook_owner: HookOwner = .{};
    godot.annotations.deinitPropertyFields(HookOwner, &hook_owner);
    check(hook_owner.probe.value.hook_called, "custom .deinit must run");
    check(!hook_owner.probe.value.deinit_called, "custom .deinit must override the best-effort cleanup");
    check(hook_owner.plain_deinit_called, "custom .deinit must run for any value type");

    // Best-effort cleanup: value types with `deinit`, independent of accessors.
    var field_owner: FieldLifetimeOwner = .{};
    godot.annotations.deinitPropertyFields(FieldLifetimeOwner, &field_owner);
    check(field_owner.probe.value.deinit_called, "struct value types declaring deinit must be deinitialized");
    check(field_owner.accessor.value.deinit_called, "custom accessors must not skip best-effort cleanup");

    // Non-property fields and classes without Property fields are no-ops.
    var no_props: NoProperties = .{};
    godot.annotations.deinitPropertyFields(NoProperties, &no_props);
    check(no_props.value == 0, "deinitPropertyFields must ignore non-property fields");

    // The managed-builtin allow-list is explicit and does not accept arbitrary
    // structs, even ones declaring `deinit`.
    check(godot.builtins.isManaged(godot.builtins.String), "String must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.StringName), "StringName must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.NodePath), "NodePath must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.Callable), "Callable must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.Signal), "Signal must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.Array), "Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.Dictionary), "Dictionary must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedByteArray), "PackedByteArray must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedColorArray), "PackedColorArray must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedFloat32Array), "PackedFloat32Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedFloat64Array), "PackedFloat64Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedInt32Array), "PackedInt32Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedInt64Array), "PackedInt64Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedStringArray), "PackedStringArray must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedVector2Array), "PackedVector2Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedVector3Array), "PackedVector3Array must be a known managed builtin");
    check(godot.builtins.isManaged(godot.builtins.PackedVector4Array), "PackedVector4Array must be a known managed builtin");
    check(!godot.builtins.isManaged(godot.builtins.Vector2), "plain value builtins are not managed builtins");
    check(!godot.builtins.isManaged(godot.builtins.Variant), "Variant is not a managed builtin");
    check(!godot.builtins.isManaged(u32), "scalars are not managed builtins");
    check(!godot.builtins.isManaged(DeinitProbe), "arbitrary structs are not known managed builtins");
    check(!godot.builtins.isManaged(?*godot.classes.core.RefCounted), "RefCounted pointers are managed by references, not deinit");
}

fn checkBestEffortPolicy() void {
    // Ownership classification drives the explicit-mode requirement.
    check(godot.annotations.property.requiresExplicitOwnership(godot.builtins.String), "String owns a managed value");
    check(godot.annotations.property.requiresExplicitOwnership(godot.builtins.StringName), "StringName owns a managed value");
    check(godot.annotations.property.requiresExplicitOwnership(godot.builtins.Variant), "Variant owns its payload");
    check(godot.annotations.property.requiresExplicitOwnership(?*godot.classes.core.RefCounted), "RefCounted pointers own a reference");
    check(godot.annotations.property.requiresExplicitOwnership(DeinitProbe), "structs declaring deinit own cleanup");
    check(!godot.annotations.property.requiresExplicitOwnership(i32), "scalars are trivial");
    check(!godot.annotations.property.requiresExplicitOwnership(godot.builtins.Vector2), "plain value builtins are trivial");
    check(!godot.annotations.property.requiresExplicitOwnership(?*godot.classes.core.Node), "plain object pointers are borrowed");
    check(!godot.annotations.property.requiresExplicitOwnership(NoProperties), "structs without deinit are trivial");

    // `.best_effort` installs a setter and cleanup but is not a custom hook.
    const probe = @FieldType(BestEffortProbeOwner, "probe");
    check(!godot.annotations.property.hasCustomSetter(probe), ".best_effort is not a custom .set");
    check(!godot.annotations.property.hasCustomDeinit(probe), ".best_effort is not a custom .deinit");
    check(!probe.has_custom_set and !probe.has_custom_deinit, "marker custom flags must exclude .best_effort");
    check(@TypeOf(godot.annotations.property.setterFn(BestEffortProbeOwner, "probe").?) == fn (*BestEffortProbeOwner, DeinitProbe) void, ".best_effort must expose the setter thunk");
    check(godot.annotations.property.deinitFn(BestEffortProbeOwner, "probe") == null, ".best_effort exposes no custom cleanup thunk");

    // A read-only managed value declares cleanup only.
    const sealed = @FieldType(ReadOnlyManagedOwner, "name");
    check(sealed.read_only, "read-only managed values stay read-only");
    check(!godot.annotations.property.hasCustomSetter(sealed), "read-only managed values have no setter");
    check(godot.annotations.property.setterFn(ReadOnlyManagedOwner, "name") == null, "read-only managed values expose no setter");
    check(!godot.annotations.property.hasCustomDeinit(sealed), "best-effort cleanup is not a custom hook");
}

/// Compile-only best-effort engine paths; managed values are never read.
fn checkBestEffortEnginePaths() void {
    const undefined_owner: *BestEffortOwner = undefined;
    godot.annotations.property.setterFn(BestEffortOwner, "string").?(undefined_owner, @as(godot.builtins.String, undefined));
    godot.annotations.property.setterFn(BestEffortOwner, "variant").?(undefined_owner, @as(godot.builtins.Variant, undefined));
    godot.annotations.property.setterFn(BestEffortOwner, "ref").?(undefined_owner, @as(?*godot.classes.core.RefCounted, null));
    godot.annotations.deinitPropertyFields(BestEffortOwner, undefined_owner);
    const undefined_read_only: *ReadOnlyManagedOwner = undefined;
    godot.annotations.deinitPropertyFields(ReadOnlyManagedOwner, undefined_read_only);
}

/// Compile-only property lifetime coverage; generic RefCounted helpers are
/// covered by `tests/ownership.zig`.
fn checkOwnershipRuntimePaths() void {
    var owner: RefLifetimeOwner = .{};
    godot.annotations.deinitPropertyFields(RefLifetimeOwner, &owner);
}

/// Compile-only `.init` coverage.
fn checkInitializerEnginePaths() void {
    var owner: BuiltinInitializerOwner = .{};
    var dummy_base: void = {};
    godot.annotations.initPropertyFields(BuiltinInitializerOwner, void, &owner, &dummy_base);
}

fn comptimeChecks() void {
    @setEvalBranchQuota(500_000);
    checkUsageNormalization();
    checkVariantTypeOverride();
    checkVariantValueProperty();
    checkDiscovery();
    checkDescriptors();
    checkAccessors();
    checkReadOnly();
    checkInitializers();
    checkMarkerIdentity();
    checkLifetime();
    checkBestEffortPolicy();
    checkGroups();
    checkNoMarkerLayout();
    checkEnumHints();
}

const GroupedOwner = struct {
    pub const Groups = godot.annotations.PropertyGroups(.{
        .{
            .name = "Combat",
            .fields = .{"health"},
            .groups = .{
                .{
                    .name = "Vitals",
                    .fields = .{"stamina"},
                    .groups = .{
                        .{ .name = "Crit", .fields = .{"crit"} },
                    },
                },
            },
        },
    });

    health: godot.annotations.Property(i32, .{ .usage = .exported }) = .init(100),
    stamina: godot.annotations.Property(f32, .{ .usage = .exported }) = .init(50),
    crit: godot.annotations.Property(i32, .{ .usage = .exported }) = .init(5),
};

fn checkGroups() void {
    const entries = godot.annotations.property.layout(GroupedOwner);
    check(entries.len == 6, "PropertyGroups layout must emit nested section and field entries");
    switch (entries[0]) {
        .section => |section| {
            check(section.depth == 0, "top-level group depth must be 0");
            check(std.mem.eql(u8, section.name, "Combat"), "top-level group name");
        },
        .field => @compileError("property tests: expected a group entry first"),
    }
    switch (entries[1]) {
        .field => |index| check(index == 0, "first group field must be the health descriptor"),
        .section => @compileError("property tests: expected the health field entry"),
    }
    switch (entries[2]) {
        .section => |section| {
            check(section.depth == 1, "nested group depth must be 1");
            check(std.mem.eql(u8, section.name, "Vitals"), "nested group name");
        },
        .field => @compileError("property tests: expected the nested group entry"),
    }
    switch (entries[3]) {
        .field => |index| check(index == 1, "nested group field must be the stamina descriptor"),
        .section => @compileError("property tests: expected the stamina field entry"),
    }
    switch (entries[4]) {
        .section => |section| {
            check(section.depth == 2, "nested subgroup depth must be 2");
            check(std.mem.eql(u8, section.name, "Crit"), "nested subgroup name");
        },
        .field => @compileError("property tests: expected the nested subgroup entry"),
    }
    switch (entries[5]) {
        .field => |index| check(index == 2, "nested subgroup field must be the crit descriptor"),
        .section => @compileError("property tests: expected the crit field entry"),
    }
}

fn checkNoMarkerLayout() void {
    const entries = godot.annotations.property.layout(CheckOwner);
    check(entries.len == 3, "layout must keep only visible fields when no marker exists");
    switch (entries[0]) {
        .field => |index| check(index == 1, "no-marker layout must keep field declaration order (1)"),
        .section => @compileError("property tests: unexpected section without a marker"),
    }
    switch (entries[1]) {
        .field => |index| check(index == 2, "no-marker layout must keep field declaration order (2)"),
        .section => @compileError("property tests: unexpected section without a marker"),
    }
    switch (entries[2]) {
        .field => |index| check(index == 3, "no-marker layout must keep field declaration order (3)"),
        .section => @compileError("property tests: unexpected section without a marker"),
    }
}

const HintMode = enum(i32) { idle, running = 3 };
const HintFlags = bitpack struct(u32) {
    first: bool = false,
    second: bool = false,
    _pad0: u30 = 0,
};

const UnregisteredMode = enum(i32) { idle, running = 3 };
const OtherMode = enum(i32) { alpha, beta = 2 };

const OtherConstantsOwner = struct {
    pub const ConstantsDecl = godot.annotations.Constants(struct {
        pub const Mode = OtherMode;
    });
};

const NodeExtension = struct {
    pub const Extends = godot.classes.core.Node;
    pub const GodotClassName = "CustomNode";
    base: godot.annotations.Base(Extends) = .{},
};

const ResourceExtension = struct {
    pub const Extends = godot.classes.core.Resource;
    pub const GodotClassName = "CustomResource";
    base: godot.annotations.Base(Extends) = .{},
};

const HintOwner = struct {
    pub const ConstantsDecl = godot.annotations.Constants(struct {
        pub const Mode = HintMode;
        pub const Flags = HintFlags;
    });

    mode: godot.annotations.Property(HintMode, .{ .usage = .exported }) = .init(.idle),
    flags: godot.annotations.Property(HintFlags, .{ .usage = .exported }) = .init(.{}),
    hidden_mode: godot.annotations.Property(HintMode, .{ .usage = .none }) = .init(.idle),
    explicit_mode: godot.annotations.Property(HintMode, .{
        .usage = .exported,
        .hint = .none,
        .hint_string = "Idle,Running",
    }) = .init(.idle),
    unregistered: godot.annotations.Property(UnregisteredMode, .{ .usage = .exported }) = .init(.idle),
    cross_class: godot.annotations.Property(OtherMode, .{ .usage = .exported }) = .init(.alpha),
    node: godot.annotations.Property(?*godot.classes.core.Node, .{ .usage = .exported }) = .init(null),
    resource: godot.annotations.Property(?*godot.classes.core.Resource, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    plain_object: godot.annotations.Property(?*godot.classes.core.Object, .{ .usage = .exported }) = .init(null),
    ref_counted: godot.annotations.Property(?*godot.classes.core.RefCounted, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    node_ext: godot.annotations.Property(?*NodeExtension, .{ .usage = .exported }) = .init(null),
    resource_ext: godot.annotations.Property(?*ResourceExtension, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
    ref_ext: godot.annotations.Property(?*RefCountedExtension, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(null),
};

fn checkEnumHints() void {
    const descs = godot.annotations.property.descriptors(HintOwner);
    check(descs[0].hint == .@"enum", "Constants enum type must set the enum hint");
    check(std.mem.eql(u8, descs[0].hint_string, "Idle:0,Running:3"), "enum hint string");
    check(descs[0].usage.class_is_enum, "enum hint must set CLASS_IS_ENUM");
    check(descs[0].class_name != null and std.mem.eql(u8, descs[0].class_name.?, "HintOwner.Mode"), "enum class name");

    check(descs[1].hint == .flags, "Constants bitfield type must set the flags hint");
    check(std.mem.eql(u8, descs[1].hint_string, "First:1,Second:2"), "bitfield hint string");
    check(descs[1].usage.class_is_bitfield, "bitfield hint must set CLASS_IS_BITFIELD");
    check(descs[1].class_name != null and std.mem.eql(u8, descs[1].class_name.?, "HintOwner.Flags"), "bitfield class name");

    check(descs[2].hint == .none, "hidden enum property must not receive an automatic hint");
    check(descs[2].class_name == null, "hidden enum property must not receive a class name");
    check(usageBits(descs[2].usage) == 0, "hidden enum property must stay hidden");

    check(descs[3].hint == .none, "explicit hint must disable automatic enum wiring");
    check(std.mem.eql(u8, descs[3].hint_string, "Idle,Running"), "explicit hint string must be kept");
    check(descs[3].class_name == null, "explicit hint must not add an enum class name");
    check(usageBits(descs[3].usage) == usageBits(.{ .storage = true, .editor = true }), "explicit hint must not add enum usage bits");

    check(descs[4].hint == .@"enum", "unregistered enum type must still get the enum hint");
    check(std.mem.eql(u8, descs[4].hint_string, "Idle:0,Running:3"), "unregistered enum hint string");
    check(descs[4].class_name == null, "unregistered enum must not claim a class name");
    check(!descs[4].usage.class_is_enum, "unregistered enum must not set CLASS_IS_ENUM");

    check(descs[5].hint == .@"enum", "cross-class enum type must get the enum hint");
    check(std.mem.eql(u8, descs[5].hint_string, "Alpha:0,Beta:2"), "cross-class enum hint string");
    check(descs[5].class_name == null, "cross-class enum must not claim this class's enum name");
    check(!descs[5].usage.class_is_enum, "cross-class enum must not set CLASS_IS_ENUM");

    check(descs[6].hint == .node_type, "Node pointers must get the node picker hint");
    check(std.mem.eql(u8, descs[6].hint_string, "Node"), "Node hint string");
    check(descs[6].class_name != null and std.mem.eql(u8, descs[6].class_name.?, "Node"), "Node class name");

    check(descs[7].hint == .resource_type, "Resource pointers must get the resource picker hint");
    check(std.mem.eql(u8, descs[7].hint_string, "Resource"), "Resource hint string");
    check(descs[7].class_name != null and std.mem.eql(u8, descs[7].class_name.?, "Resource"), "Resource class name");

    check(descs[8].hint == .none, "plain object pointers must not get a picker hint");
    check(std.mem.eql(u8, descs[8].hint_string, ""), "plain object pointers keep an empty hint string");
    check(descs[8].class_name != null and std.mem.eql(u8, descs[8].class_name.?, "Object"), "plain object class name");

    check(descs[9].hint == .none, "non-Resource RefCounted pointers must not get a picker hint");
    check(descs[9].class_name != null and std.mem.eql(u8, descs[9].class_name.?, "RefCounted"), "RefCounted class name");

    check(descs[10].hint == .node_type, "extension Node pointers must get the node picker hint");
    check(std.mem.eql(u8, descs[10].hint_string, "CustomNode"), "extension Node hint string uses GodotClassName");
    check(descs[10].class_name != null and std.mem.eql(u8, descs[10].class_name.?, "CustomNode"), "extension Node class name");

    check(descs[11].hint == .resource_type, "extension Resource pointers must get the resource picker hint");
    check(std.mem.eql(u8, descs[11].hint_string, "CustomResource"), "extension Resource hint string uses GodotClassName");
    check(descs[11].class_name != null and std.mem.eql(u8, descs[11].class_name.?, "CustomResource"), "extension Resource class name");

    check(descs[12].hint == .none, "non-Resource RefCounted extension pointers must not get a picker hint");
    check(descs[12].class_name != null and std.mem.eql(u8, descs[12].class_name.?, "RefCountedExtension"), "extension RefCounted class name");
}

comptime {
    comptimeChecks();
    _ = &checkBestEffortEnginePaths;
    _ = &checkOwnershipRuntimePaths;
    _ = &checkInitializerEnginePaths;
}

test "best-effort setter stores without cleanup and cleanup deinitializes" {
    var owner: BestEffortProbeOwner = .{};
    const set = godot.annotations.property.setterFn(BestEffortProbeOwner, "probe").?;
    set(&owner, .{});
    try std.testing.expect(!owner.probe.value.deinit_called);

    godot.annotations.deinitPropertyFields(BestEffortProbeOwner, &owner);
    try std.testing.expect(owner.probe.value.deinit_called);

    var direct: DeinitProbe = .{};
    godot.annotations.property.setBestEffort(DeinitProbe, &direct, .{});
    try std.testing.expect(!direct.deinit_called);
    godot.annotations.property.deinitBestEffort(DeinitProbe, &direct);
    try std.testing.expect(direct.deinit_called);
}

const std = @import("std");

const godot = @import("godot");
