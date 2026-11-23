//! `Property` field annotation, `PropertyGroups` layout, option normalization,
//! accessors, discovery, and lifetime helpers. See docs/properties.md.

/// How a writable property replaces its stored value.
const SetMode = enum { plain, best_effort, custom };

/// How `deinitPropertyFields` releases a stored value.
const DeinitMode = enum { none, best_effort, custom };

/// A direct field type that stores a Zig value and declares an engine property.
/// Options and lifetime rules: docs/properties.md.
pub fn Property(comptime T: type, comptime p_options: anytype) type {
    // `stringToEnum` builds and sorts a static map; PropertyHint exceeds the default quota.
    @setEvalBranchQuota(500_000);
    const normalized = normalizeOptions(T, p_options);
    return struct {
        pub const PropertyFor = T;
        pub const options = p_options;
        pub const name = normalized.name;
        pub const usage = normalized.usage;
        pub const hint = normalized.hint;
        pub const hint_string: [:0]const u8 = normalized.hint_string;
        pub const variant_type: ?interface.VariantType = normalized.variant_type;
        pub const read_only = normalized.read_only;
        pub const has_custom_get = @hasField(@TypeOf(p_options), "get");
        pub const has_custom_set = normalized.set_mode == .custom;
        pub const has_custom_init = @hasField(@TypeOf(p_options), "init");
        pub const has_custom_deinit = normalized.deinit_mode == .custom;
        const set_mode = normalized.set_mode;
        const deinit_mode = normalized.deinit_mode;
        pub const marker = marker_kind.Kind.property;

        value: T,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn get(self: *const Self) T {
            return self.value;
        }

        pub fn getPtr(self: *Self) *T {
            return &self.value;
        }

        pub fn getPtrConst(self: *const Self) *const T {
            return &self.value;
        }

        /// Literal set, doesn't perform any Variant borrow/copy or refcount unreference/reference.
        pub fn set(self: *Self, value: T) void {
            self.value = value;
        }

        /// Adds an eager `.init` option; equivalent to `.init = Init(T, func, args)`.
        pub fn Init(comptime func: anytype, comptime args: anytype) type {
            const OptionsT = @TypeOf(p_options);
            if (comptime @hasField(OptionsT, "init")) {
                @compileError("Property<" ++ @typeName(T) ++ "> already has an '.init' option; chain '.Init' only once");
            }

            const ExtendedOptions = reflect.AppendStructField(OptionsT, "init", type);
            const extended: ExtendedOptions = comptime blk: {
                var value: ExtendedOptions = undefined;
                for (@typeInfo(OptionsT).@"struct".field_names) |option_name| {
                    @field(value, option_name) = @field(p_options, option_name);
                }
                value.init = init_mod.Init(T, func, args);
                break :blk value;
            };
            return Property(T, extended);
        }
    };
}

/// True when `T` needs explicit `.set`/`.deinit` modes. See docs/properties.md.
pub fn requiresExplicitOwnership(comptime T: type) bool {
    return builtins.isManaged(T) or T == builtins.Variant or
        reflect.isRefCountedPointer(T) or hasValueDeinit(T);
}

/// Replaces a stored value: deinitialize an owned managed builtin or `Variant`,
/// retain/release `RefCounted` pointers, otherwise assign. The new value is
/// stored even when it is the current value.
pub fn setBestEffort(comptime T: type, field: *T, value: T) void {
    if (comptime builtins.isManaged(T) or T == builtins.Variant) {
        field.deinit();
    } else if (comptime reflect.isRefCountedPointer(T)) {
        // Take the new reference first: assigning the current object back must
        // not release the last reference before retaining it.
        ownership.retainRefCounted(T, value);
        ownership.releaseRefCounted(T, field.*);
    }
    field.* = value;
}

/// Releases a stored value: call a user struct's `deinit` or release a
/// `RefCounted` reference; other value types need no cleanup.
pub fn deinitBestEffort(comptime T: type, field: *T) void {
    if (comptime hasValueDeinit(T)) {
        field.deinit();
    } else if (comptime reflect.isRefCountedPointer(T)) {
        ownership.releaseRefCounted(T, field.*);
    }
}

/// Declares the inspector section tree for a class's visible `Property` fields.
/// Every visible field must be listed exactly once; nesting gives the section
/// depth. The marker declaration name is free.
pub fn PropertyGroups(comptime p_groups: anytype) type {
    @setEvalBranchQuota(1_000_000);
    validateGroupDecls(p_groups);
    return struct {
        pub const groups = p_groups;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.property_groups;
    };
}

/// One inspector section emitted before its fields.
pub const Section = struct {
    name: [:0]const u8,
    /// 0 for a top-level group, 1 for its subgroup, and so on.
    depth: u32,
};

/// One entry in the property list layout: a section header or a field index.
pub const LayoutEntry = union(enum) {
    section: Section,
    field: u32,
};

/// Comptime metadata for one `Property` field.
pub const PropertyDescriptor = struct {
    field_name: [:0]const u8,
    godot_name: [:0]const u8,
    value_type: type,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    /// `<Class>.<Name>` for a same-class `Constants` enum/bitfield, the object
    /// class name for a visible object pointer, null otherwise. Registration
    /// falls back to `conversion.engineClassName(value_type)` when null.
    class_name: ?[:0]const u8,
    type: ?interface.VariantType,
};

/// Finds `Property` fields declared directly on `T`, in declaration order.
pub fn findPropertyFieldNames(comptime T: type) []const [:0]const u8 {
    return PropertyFieldNamesCache(T).value;
}

fn PropertyFieldNamesCache(comptime T: type) type {
    return struct {
        const value = computePropertyFieldNames(T);
    };
}

fn computePropertyFieldNames(comptime T: type) []const [:0]const u8 {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") @compileError("Expected struct type, found: " ++ @typeName(T));
        const info = type_info.@"struct";
        var names: [info.field_names.len][:0]const u8 = undefined;
        var n: usize = 0;
        for (info.field_names, info.field_types) |name, F| {
            if (!reflect.isNormalStruct(F)) continue;
            if (!isPropertyField(F)) continue;
            names[n] = name;
            n += 1;
        }
        const out = names[0..n].*;
        return &out;
    }
}

/// Descriptor table for `T`, in declaration order; duplicate engine names are a
/// compile error.
pub fn descriptors(comptime T: type) [findPropertyFieldNames(T).len]PropertyDescriptor {
    return DescriptorTable(T).value;
}

fn DescriptorTable(comptime T: type) type {
    return struct {
        const value = computeDescriptors(T);
    };
}

fn computeDescriptors(comptime T: type) [findPropertyFieldNames(T).len]PropertyDescriptor {
    const names = findPropertyFieldNames(T);
    var out: [names.len]PropertyDescriptor = undefined;
    inline for (names, 0..) |field_name, i| {
        out[i] = descriptorFor(T, field_name);
    }
    inline for (0..out.len) |i| {
        inline for (i + 1..out.len) |j| {
            if (std.mem.eql(u8, out[i].godot_name, out[j].godot_name)) {
                @compileError(std.fmt.comptimePrint(
                    "Duplicate property engine name '{s}' on class '{s}': fields '{s}' and '{s}' " ++
                        "both map to it. Set an explicit '.name' on one of the fields.",
                    .{ out[i].godot_name, @typeName(T), out[i].field_name, out[j].field_name },
                ));
            }
        }
    }
    return out;
}

/// True when `F` is a type produced by `Property`.
pub fn isPropertyField(comptime F: type) bool {
    if (@typeInfo(F) != .@"struct") return false;
    if (!marker_kind.is(F, .property)) return false;
    if (!@hasDecl(F, "PropertyFor") or
        !@hasDecl(F, "options")) return false;
    return F == Property(F.PropertyFor, F.options);
}

/// Returns `T`'s `PropertyGroups` marker, or an empty slice.
pub fn findPropertyGroups(comptime T: type) []const type {
    return PropertyGroupsCache(T).value;
}

fn PropertyGroupsCache(comptime T: type) type {
    return struct {
        const value = computePropertyGroups(T);
    };
}

fn computePropertyGroups(comptime T: type) []const type {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("Expected a class struct, found: " ++ @typeName(T));

        var found: [1]type = undefined;
        var count: usize = 0;
        for (@typeInfo(T).@"struct".decl_names) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isPropertyGroups(Decl)) continue;
            if (count != 0) @compileError(std.fmt.comptimePrint(
                "Class '{s}' declares more than one PropertyGroups marker; keep a single layout declaration.",
                .{@typeName(T)},
            ));
            found[0] = Decl;
            count = 1;
        }
        const out = found[0..count].*;
        return &out;
    }
}

/// Property-list layout: section headers interleaved with visible field indices.
///
/// Without a `PropertyGroups` marker this is the visible fields in declaration
/// order. With a marker it is the declared section tree; every visible field
/// must be listed exactly once.
pub fn layout(comptime T: type) []const LayoutEntry {
    return LayoutCache(T).value;
}

fn LayoutCache(comptime T: type) type {
    return struct {
        const value = computeLayout(T);
    };
}

fn computeLayout(comptime T: type) []const LayoutEntry {
    comptime {
        const descs = descriptors(T);
        const descs_slice = descs[0..];
        const marker = findPropertyGroups(T);
        if (marker.len == 0) return visibleLayout(descs_slice);

        const groups = marker[0].groups;
        const section_count = sectionCount(groups);
        const visible_count = visibleCount(descs_slice);
        var entries: [section_count + visible_count]LayoutEntry = undefined;
        var count: usize = 0;
        var seen: [descs.len]bool = @splat(false);
        var field_count: usize = 0;
        const map = descriptorMap(descs_slice);
        flattenGroups(groups, 0, T, descs_slice, map, &entries, &count, &seen, &field_count);

        for (descs_slice, 0..) |desc, i| {
            if (usageBits(desc.usage) != 0 and !seen[i]) @compileError(std.fmt.comptimePrint(
                "Visible property '{s}' on class '{s}' is not listed in PropertyGroups. " ++
                    "List it or set '.usage = .none'.",
                .{ desc.field_name, @typeName(T) },
            ));
        }

        const out = entries[0..count].*;
        return &out;
    }
}

fn isPropertyGroups(comptime OtherT: type) bool {
    if (!marker_kind.is(OtherT, .property_groups)) return false;
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "groups")) return false;
    return OtherT == PropertyGroups(OtherT.groups);
}

fn visibleCount(comptime descs: []const PropertyDescriptor) usize {
    var total: usize = 0;
    for (descs) |desc| {
        if (usageBits(desc.usage) != 0) total += 1;
    }
    return total;
}

fn visibleLayout(comptime descs: []const PropertyDescriptor) []const LayoutEntry {
    var entries: [visibleCount(descs)]LayoutEntry = undefined;
    var count: usize = 0;
    for (descs, 0..) |desc, i| {
        if (usageBits(desc.usage) != 0) {
            entries[count] = .{ .field = @intCast(i) };
            count += 1;
        }
    }
    const out = entries[0..count].*;
    return &out;
}

fn descriptorMap(comptime descs: []const PropertyDescriptor) std.StaticStringMap(u32) {
    const Pair = struct { []const u8, u32 };
    var pairs: [descs.len]Pair = undefined;
    for (descs, 0..) |desc, i| {
        pairs[i] = .{ desc.field_name, @intCast(i) };
    }
    return std.StaticStringMap(u32).initComptime(pairs);
}

fn sectionCount(comptime groups: anytype) usize {
    comptime {
        var total: usize = 0;
        for (groups) |group| {
            total += 1;
            if (@hasField(@TypeOf(group), "groups")) {
                const children = group.groups;
                if (tupleLen(children) != 0) total += sectionCount(children);
            }
        }
        return total;
    }
}

fn flattenGroups(
    comptime groups: anytype,
    comptime depth: u32,
    comptime Class: type,
    comptime descs: []const PropertyDescriptor,
    comptime map: std.StaticStringMap(u32),
    entries: []LayoutEntry,
    count: *usize,
    seen: []bool,
    field_count: *usize,
) void {
    for (groups) |group| {
        const name: [:0]const u8 = group.name;
        entries[count.*] = .{ .section = .{ .name = name, .depth = depth } };
        count.* += 1;

        const before = field_count.*;
        if (@hasField(@TypeOf(group), "fields")) {
            const fields = group.fields;
            if (tupleLen(fields) != 0) appendFields(fields, name, Class, descs, map, entries, count, seen, field_count);
        }
        if (@hasField(@TypeOf(group), "groups")) {
            const children = group.groups;
            if (tupleLen(children) != 0) {
                flattenGroups(children, depth + 1, Class, descs, map, entries, count, seen, field_count);
            }
        }
        if (field_count.* == before) @compileError(std.fmt.comptimePrint(
            "PropertyGroups section '{s}' on class '{s}' contains no fields; add a field or remove the section.",
            .{ name, @typeName(Class) },
        ));
    }
}

fn appendFields(
    comptime fields: anytype,
    comptime section_name: [:0]const u8,
    comptime Class: type,
    comptime descs: []const PropertyDescriptor,
    comptime map: std.StaticStringMap(u32),
    entries: []LayoutEntry,
    count: *usize,
    seen: []bool,
    field_count: *usize,
) void {
    for (fields) |field_name| {
        const name: [:0]const u8 = field_name;
        const index = map.get(name) orelse @compileError(std.fmt.comptimePrint(
            "PropertyGroups section '{s}' on class '{s}' lists unknown property field '{s}'; " ++
                "it must name a field with a Property annotation.",
            .{ section_name, @typeName(Class), name },
        ));
        const desc = descs[index];
        if (usageBits(desc.usage) == 0) @compileError(std.fmt.comptimePrint(
            "PropertyGroups section '{s}' on class '{s}' lists hidden property field '{s}'; " ++
                "remove it or give the property a non-zero usage.",
            .{ section_name, @typeName(Class), name },
        ));
        if (seen[index]) @compileError(std.fmt.comptimePrint(
            "Property field '{s}' on class '{s}' is listed more than once in PropertyGroups.",
            .{ name, @typeName(Class) },
        ));
        seen[index] = true;
        entries[count.*] = .{ .field = index };
        count.* += 1;
        field_count.* += 1;
    }
}

fn tupleLen(comptime value: anytype) usize {
    const info = @typeInfo(@TypeOf(value));
    if (info != .@"struct") @compileError("PropertyGroups entries must be tuples, found: " ++ @typeName(@TypeOf(value)));
    return info.@"struct".field_names.len;
}

fn validateGroupDecls(comptime groups: anytype) void {
    const info = @typeInfo(@TypeOf(groups));
    if (info != .@"struct" or !info.@"struct".is_tuple) @compileError(
        "PropertyGroups expects a tuple of group declarations, e.g. " ++
            ".{ .{ .name = \"Combat\", .fields = .{\"health\"} } }; found: " ++ @typeName(@TypeOf(groups)),
    );
    if (info.@"struct".field_names.len == 0) @compileError("PropertyGroups needs at least one group declaration");
    for (groups) |group| validateGroup(group);
}

fn validateGroup(comptime group: anytype) void {
    const T = @TypeOf(group);
    const info = @typeInfo(T);
    if (info != .@"struct" or info.@"struct".is_tuple) @compileError(
        "PropertyGroups group declarations must be structs with a '.name' field, found: " ++ @typeName(T),
    );
    for (info.@"struct".field_names) |field_name| {
        if (!std.mem.eql(u8, field_name, "name") and
            !std.mem.eql(u8, field_name, "fields") and
            !std.mem.eql(u8, field_name, "groups"))
        {
            @compileError(std.fmt.comptimePrint(
                "PropertyGroups group has unknown field '.{s}'. Supported fields: .name, .fields, .groups.",
                .{field_name},
            ));
        }
    }
    if (!@hasField(T, "name")) @compileError("PropertyGroups group is missing the required '.name' field");
    const name: [:0]const u8 = group.name;
    if (name.len == 0) @compileError("PropertyGroups group '.name' must not be empty");
    if (@hasField(T, "fields")) validateFieldList(group.fields);
    if (@hasField(T, "groups")) {
        const children = group.groups;
        if (tupleLen(children) != 0) validateGroupDecls(children);
    }
}

fn validateFieldList(comptime fields: anytype) void {
    const info = @typeInfo(@TypeOf(fields));
    if (info != .@"struct") @compileError("PropertyGroups '.fields' must be a tuple of property field names");
    if (info.@"struct".field_names.len == 0) return;
    if (!info.@"struct".is_tuple) @compileError("PropertyGroups '.fields' must be a tuple of property field names");
    for (fields) |field_name| {
        const name: [:0]const u8 = field_name;
        if (name.len == 0) @compileError("PropertyGroups property field name must not be empty");
    }
}

/// The value type stored by a `Property` field wrapper.
pub fn PropertyValueType(comptime F: type) type {
    if (comptime !isPropertyField(F)) @compileError("Expected a Property field type, found: " ++ @typeName(F));
    return F.PropertyFor;
}

/// True when the field's options declare a custom `.get`.
pub fn hasCustomGetter(comptime F: type) bool {
    if (comptime !isPropertyField(F)) @compileError("Expected a Property field type, found: " ++ @typeName(F));
    return F.has_custom_get;
}

/// True when the field's options declare a custom `.set`.
pub fn hasCustomSetter(comptime F: type) bool {
    if (comptime !isPropertyField(F)) @compileError("Expected a Property field type, found: " ++ @typeName(F));
    return F.has_custom_set;
}

/// True when the field's options declare an `.init` creation-time initializer.
pub fn hasCustomInitializer(comptime F: type) bool {
    if (comptime !isPropertyField(F)) @compileError("Expected a Property field type, found: " ++ @typeName(F));
    return F.has_custom_init;
}

/// Getter thunk: the custom `.get` or a read of `.value`.
pub fn getterFn(comptime Owner: type, comptime field_name: [:0]const u8) fn (*Owner) PropertyValueType(@FieldType(Owner, field_name)) {
    const F = RequirePropertyField(Owner, field_name);
    const Value = F.PropertyFor;
    if (comptime hasCustomGetter(F)) {
        validateGetterOwner(Owner, field_name, Value);
        const get = @field(F.options, "get");
        return get;
    }
    return struct {
        fn getValue(owner: *Owner) Value {
            return @field(owner, field_name).value;
        }
    }.getValue;
}

/// Setter thunk, or null when `.read_only`. `.best_effort` reproduces the
/// built-in ownership policy; a missing `.set` on a trivial value type is plain
/// assignment.
pub fn setterFn(comptime Owner: type, comptime field_name: [:0]const u8) ?fn (*Owner, PropertyValueType(@FieldType(Owner, field_name))) void {
    const F = RequirePropertyField(Owner, field_name);
    const Value = F.PropertyFor;
    if (comptime F.read_only) return null;
    switch (comptime F.set_mode) {
        .custom => {
            validateSetterOwner(Owner, field_name);
            const set = @field(F.options, "set");
            return set;
        },
        .best_effort => return struct {
            fn setValue(owner: *Owner, value: Value) void {
                setBestEffort(Value, &@field(owner, field_name).value, value);
            }
        }.setValue,
        .plain => return struct {
            fn setValue(owner: *Owner, value: Value) void {
                @field(owner, field_name).value = value;
            }
        }.setValue,
    }
}

/// True when engine `set` dispatch can write a `Property` field.
pub fn isWritable(comptime Owner: type, comptime field_name: [:0]const u8) bool {
    return setterFn(Owner, field_name) != null;
}

/// True when engine `set` dispatch must reject a `Property` field.
pub fn isReadOnly(comptime Owner: type, comptime field_name: [:0]const u8) bool {
    return setterFn(Owner, field_name) == null;
}

// Creation-time initializers. These are explicit: `.init` is not engine
// dispatch and not an OnReady strategy; the instance owner calls
// `initPropertyFields` once during instance creation. Registration does so from
// the create-instance callback.

/// Runs every `.init` initializer once during creation; no-op for other fields.
pub fn initPropertyFields(comptime T: type, comptime Base: type, owner: *T, base: *Base) void {
    comptime if (@typeInfo(T) != .@"struct") @compileError(
        "initPropertyFields expects an extension class struct type, found: " ++ @typeName(T),
    );
    inline for (comptime findPropertyFieldNames(T)) |field_name| {
        initPropertyField(T, Base, field_name, owner, base);
    }
}

fn initPropertyField(
    comptime T: type,
    comptime Base: type,
    comptime field_name: [:0]const u8,
    owner: *T,
    base: *Base,
) void {
    const F = @FieldType(T, field_name);
    if (comptime !hasCustomInitializer(F)) return;
    const initializer = @field(F.options, "init");
    @field(owner, field_name).value = initializer.call(T, Base, owner, base);
}

// Lifetime tools. These are explicit: nothing runs automatically, and the
// caller guarantees the fields hold valid values (never `undefined`).

/// True when the field's options declare a custom `.deinit` cleanup hook.
pub fn hasCustomDeinit(comptime F: type) bool {
    if (comptime !isPropertyField(F)) @compileError("Expected a Property field type, found: " ++ @typeName(F));
    return F.has_custom_deinit;
}

/// Custom `.deinit` thunk, or null. `.best_effort` is not a custom hook;
/// `deinitPropertyFields` branches on the declared mode instead.
pub fn deinitFn(comptime Owner: type, comptime field_name: [:0]const u8) ?fn (*Owner) void {
    const F = RequirePropertyField(Owner, field_name);
    if (comptime !hasCustomDeinit(F)) return null;
    validateDeinitOwner(Owner, field_name);
    const deinit_hook = @field(F.options, "deinit");
    return deinit_hook;
}

/// Runs every field's declared cleanup policy: custom `.deinit`, `.best_effort`,
/// or nothing. Fields must be valid; does not free the instance.
pub fn deinitPropertyFields(comptime T: type, instance: *T) void {
    comptime if (@typeInfo(T) != .@"struct") @compileError(
        "deinitPropertyFields expects an extension class struct type, found: " ++ @typeName(T),
    );
    inline for (comptime findPropertyFieldNames(T)) |field_name| {
        deinitPropertyField(T, field_name, instance);
    }
}

fn deinitPropertyField(comptime T: type, comptime field_name: [:0]const u8, instance: *T) void {
    const F = @FieldType(T, field_name);
    const Value = F.PropertyFor;
    switch (comptime F.deinit_mode) {
        .custom => deinitFn(T, field_name).?(instance),
        .best_effort => deinitBestEffort(Value, &@field(instance, field_name).value),
        .none => {},
    }
}

/// True when `T` is a struct value type declaring `deinit`.
fn hasValueDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "deinit"),
        else => false,
    };
}

const NormalizedOptions = struct {
    name: ?[:0]const u8,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    variant_type: ?interface.VariantType,
    read_only: bool,
    set_mode: SetMode,
    deinit_mode: DeinitMode,
};

const option_keys = [_][]const u8{ "usage", "name", "hint", "hint_string", "type", "get", "set", "read_only", "init", "deinit" };
const OptionKeysFormatter = struct {
    pub fn format(_: @This(), w: *std.Io.Writer) !void {
        if (comptime option_keys.len == 0) return;
        try w.writeAll(".");
        try w.writeAll(option_keys[0]);
        if (comptime option_keys.len == 1) return;
        inline for (option_keys[1..]) |key| {
            try w.writeAll(", .");
            try w.writeAll(key);
        }
    }
};

fn isKnownOption(comptime key: []const u8) bool {
    inline for (option_keys) |known| {
        if (std.mem.eql(u8, key, known)) return true;
    }
    return false;
}

fn normalizeOptions(comptime T: type, comptime options: anytype) NormalizedOptions {
    const OptionsT = @TypeOf(options);
    const info = @typeInfo(OptionsT);
    if (info != .@"struct" or info.@"struct".is_tuple or info.@"struct".layout == .@"bitpack") {
        @compileError("Property<" ++ @typeName(T) ++ "> options must be an anonymous struct literal, e.g. .{ .usage = ... }; found: " ++ @typeName(OptionsT));
    }
    inline for (info.@"struct".field_names) |key| {
        if (!isKnownOption(key)) {
            @compileError(std.fmt.comptimePrint(
                "Property<{s}> has unknown option '.{s}'. Supported options: {f}.",
                .{ @typeName(T), key, OptionKeysFormatter{} },
            ));
        }
    }
    if (!@hasField(OptionsT, "usage")) {
        @compileError("Property<" ++ @typeName(T) ++ "> is missing the required '.usage' option");
    }

    const name: ?[:0]const u8 = if (@hasField(OptionsT, "name")) options.name else null;
    if (name) |explicit_name| {
        if (explicit_name.len == 0) @compileError("Property<" ++ @typeName(T) ++ "> .name must not be empty");
    }
    if (@hasField(OptionsT, "get")) validateGetterShape(T, options.get);
    const read_only: bool = if (@hasField(OptionsT, "read_only")) blk: {
        if (@TypeOf(options.read_only) != bool) @compileError(
            "Property<" ++ @typeName(T) ++ "> .read_only must be a bool, found: " ++ @typeName(@TypeOf(options.read_only)),
        );
        break :blk options.read_only;
    } else false;
    if (@hasField(OptionsT, "set") and read_only) {
        @compileError("Property<" ++ @typeName(T) ++ "> cannot combine '.read_only = true' with a '.set' option; " ++
            "a read-only property has no engine setter. Remove one of them.");
    }
    const set_mode: SetMode = if (@hasField(OptionsT, "set"))
        normalizeSetMode(T, options.set)
    else
        .plain;
    const deinit_mode: DeinitMode = if (@hasField(OptionsT, "deinit"))
        normalizeDeinitMode(T, options.deinit)
    else
        .none;
    if (comptime requiresExplicitOwnership(T)) {
        if (comptime !read_only and set_mode == .plain) @compileError(
            "Property<" ++ @typeName(T) ++ "> stores a managed/heap value; declare '.set = .best_effort' or a setter function, or mark it '.read_only = true'",
        );
        if (comptime deinit_mode == .none) @compileError(
            "Property<" ++ @typeName(T) ++ "> stores a managed/heap value; declare '.deinit = .best_effort' or a cleanup function",
        );
    }
    if (@hasField(OptionsT, "init")) validateInitializerShape(T, options.init);
    const variant_type: ?interface.VariantType = if (@hasField(OptionsT, "type"))
        normalizeVariantType(T, options.type)
    else
        null;

    const hint_string_input: []const u8 = if (@hasField(OptionsT, "hint_string")) options.hint_string else "";
    // Options are comptime; copy to a sentinel slice once for static String
    // caching and storage in the process-lifetime PropertyInfo table.
    const hint_string: [:0]const u8 = std.fmt.comptimePrint("{s}", .{hint_string_input});
    return .{
        .name = name,
        .usage = normalizeUsage(T, options.usage),
        .hint = if (@hasField(OptionsT, "hint")) normalizeHint(T, options.hint) else .none,
        .hint_string = hint_string,
        .variant_type = variant_type,
        .read_only = read_only,
        .set_mode = set_mode,
        .deinit_mode = deinit_mode,
    };
}

fn normalizeUsage(comptime T: type, comptime usage: anytype) enums.PropertyUsageFlags {
    const UsageT = @TypeOf(usage);
    if (UsageT == enums.PropertyUsageFlags) return usage;
    if (UsageT == @TypeOf(.enum_literal)) {
        const tag = @tagName(usage);
        if (!@hasDecl(enums.PropertyUsageFlags, tag)) {
            @compileError("Property<" ++ @typeName(T) ++ "> has unknown .usage literal '." ++ tag ++
                "'; expected a PropertyUsageFlags value, a named flag preset literal, or an anonymous flag struct");
        }
        return @field(enums.PropertyUsageFlags, tag);
    }
    const info = @typeInfo(UsageT);
    if (info != .@"struct" or info.@"struct".is_tuple or info.@"struct".layout == .@"bitpack") {
        @compileError("Property<" ++ @typeName(T) ++ "> .usage must be a PropertyUsageFlags value, a named usage literal, " ++
            "or an anonymous struct of flags such as .{ .storage = true, .editor = true }; found: " ++ @typeName(UsageT));
    }
    var flags: enums.PropertyUsageFlags = .{};
    inline for (info.@"struct".field_names) |flag| {
        if (std.mem.startsWith(u8, flag, "_")) {
            @compileError("Property<" ++ @typeName(T) ++ "> .usage flag '." ++ flag ++ "' is internal padding and cannot be set");
        }
        if (!@hasField(enums.PropertyUsageFlags, flag)) {
            @compileError("Property<" ++ @typeName(T) ++ "> has unknown .usage flag '." ++ flag ++
                "'; expected a field of enums.PropertyUsageFlags");
        }
        if (@TypeOf(@field(usage, flag)) != bool) {
            @compileError("Property<" ++ @typeName(T) ++ "> .usage flag '." ++ flag ++ "' must be a bool");
        }
        @field(flags, flag) = @field(usage, flag);
    }
    return flags;
}

fn normalizeVariantType(comptime T: type, comptime variant_type: anytype) interface.VariantType {
    const VariantTypeT = @TypeOf(variant_type);
    const result: interface.VariantType = if (VariantTypeT == interface.VariantType)
        variant_type
    else if (VariantTypeT == @TypeOf(.enum_literal))
        std.meta.stringToEnum(interface.VariantType, @tagName(variant_type)) orelse
            @compileError("Property<" ++ @typeName(T) ++ "> has unknown .type literal '." ++ @tagName(variant_type) ++ "'")
    else
        @compileError("Property<" ++ @typeName(T) ++ "> .type must be an interface.VariantType value or an enum literal such as .object; found: " ++ @typeName(VariantTypeT));
    if (result == .nil or result == .variant_max) {
        @compileError("Property<" ++ @typeName(T) ++ "> .type must be a concrete value type, not ." ++ @tagName(result));
    }
    return result;
}

fn normalizeHint(comptime T: type, comptime hint: anytype) enums.PropertyHint {
    const HintT = @TypeOf(hint);
    if (HintT == enums.PropertyHint) return hint;
    if (HintT == @TypeOf(.enum_literal)) {
        const tag = @tagName(hint);
        return std.meta.stringToEnum(enums.PropertyHint, tag) orelse
            @compileError("Property<" ++ @typeName(T) ++ "> has unknown .hint literal '." ++ tag ++ "'");
    }
    @compileError("Property<" ++ @typeName(T) ++ "> .hint must be a PropertyHint value or an enum literal such as .range; found: " ++ @typeName(HintT));
}

fn normalizeSetMode(comptime T: type, comptime set: anytype) SetMode {
    if (@TypeOf(set) == @TypeOf(.enum_literal)) {
        const tag = @tagName(set);
        if (comptime std.mem.eql(u8, tag, "best_effort")) return .best_effort;
        @compileError("Property<" ++ @typeName(T) ++ "> has unknown .set literal '." ++ tag ++
            "'; expected '.best_effort' or a setter function");
    }
    validateSetterShape(T, set);
    return .custom;
}

fn normalizeDeinitMode(comptime T: type, comptime deinit_hook: anytype) DeinitMode {
    if (@TypeOf(deinit_hook) == @TypeOf(.enum_literal)) {
        const tag = @tagName(deinit_hook);
        if (comptime std.mem.eql(u8, tag, "best_effort")) return .best_effort;
        @compileError("Property<" ++ @typeName(T) ++ "> has unknown .deinit literal '." ++ tag ++
            "'; expected '.best_effort' or a cleanup function");
    }
    validateDeinitShape(T, deinit_hook);
    return .custom;
}

fn isSingleItemPointer(comptime P: type) bool {
    const info = @typeInfo(P);
    return info == .pointer and info.pointer.size == .one;
}

/// Accessor shape checks; the owner is validated separately.
fn validateGetterShape(comptime T: type, comptime get: anytype) void {
    if (@TypeOf(get) == type) @compileError("Property<" ++ @typeName(T) ++ "> .get must be a function, found a type");
    const info = @typeInfo(@TypeOf(get));
    if (info != .@"fn") @compileError("Property<" ++ @typeName(T) ++ "> .get must be a function, found: " ++ @typeName(@TypeOf(get)));
    const fn_info = info.@"fn";
    if (fn_info.is_generic) @compileError("Property<" ++ @typeName(T) ++ "> .get must be a normal runtime function, not a generic one");
    const ReturnT = fn_info.return_type orelse
        @compileError("Property<" ++ @typeName(T) ++ "> .get must return " ++ @typeName(T));
    if (ReturnT != T) {
        @compileError("Property<" ++ @typeName(T) ++ "> .get must return " ++ @typeName(T) ++ ", found: " ++ @typeName(ReturnT));
    }
    if (fn_info.param_types.len != 1) {
        @compileError(std.fmt.comptimePrint(
            "Property<{s}> .get must accept exactly one owner parameter ('*Owner' or '*const Owner'), found {d} parameters",
            .{ @typeName(T), fn_info.param_types.len },
        ));
    }
    const OwnerParam = fn_info.param_types[0].?;
    if (!isSingleItemPointer(OwnerParam)) {
        @compileError("Property<" ++ @typeName(T) ++ "> .get parameter must be a single-item owner pointer " ++
            "('*Owner' or '*const Owner'), found: " ++ @typeName(OwnerParam));
    }
}

/// Accessor shape checks; the owner is validated separately.
fn validateSetterShape(comptime T: type, comptime set: anytype) void {
    if (@TypeOf(set) == type) @compileError("Property<" ++ @typeName(T) ++ "> .set must be a function, found a type");
    const info = @typeInfo(@TypeOf(set));
    if (info != .@"fn") @compileError("Property<" ++ @typeName(T) ++ "> .set must be a function, found: " ++ @typeName(@TypeOf(set)));
    const fn_info = info.@"fn";
    if (fn_info.is_generic) @compileError("Property<" ++ @typeName(T) ++ "> .set must be a normal runtime function, not a generic one");
    const ReturnT = fn_info.return_type orelse
        @compileError("Property<" ++ @typeName(T) ++ "> .set must return void");
    if (ReturnT != void) {
        @compileError("Property<" ++ @typeName(T) ++ "> .set must return void, found: " ++ @typeName(ReturnT));
    }
    if (fn_info.param_types.len != 2) {
        @compileError(std.fmt.comptimePrint(
            "Property<{s}> .set must accept exactly two parameters ('*Owner' and '{s}'), found {d} parameters",
            .{ @typeName(T), @typeName(T), fn_info.param_types.len },
        ));
    }
    const OwnerParam = fn_info.param_types[0].?;
    if (!isSingleItemPointer(OwnerParam)) {
        @compileError("Property<" ++ @typeName(T) ++ "> .set first parameter must be '*Owner', found: " ++ @typeName(OwnerParam));
    }
    const ValueParam = fn_info.param_types[1].?;
    if (ValueParam != T) {
        @compileError("Property<" ++ @typeName(T) ++ "> .set second parameter must be " ++ @typeName(T) ++ ", found: " ++ @typeName(ValueParam));
    }
}

/// Deinit shape check; the owner is validated separately.
fn validateDeinitShape(comptime T: type, comptime deinit_hook: anytype) void {
    if (@TypeOf(deinit_hook) == type) @compileError("Property<" ++ @typeName(T) ++ "> .deinit must be a function, found a type");
    const info = @typeInfo(@TypeOf(deinit_hook));
    if (info != .@"fn") @compileError("Property<" ++ @typeName(T) ++ "> .deinit must be a function, found: " ++ @typeName(@TypeOf(deinit_hook)));
    const fn_info = info.@"fn";
    if (fn_info.is_generic) @compileError("Property<" ++ @typeName(T) ++ "> .deinit must be a normal runtime function, not a generic one");
    const ReturnT = fn_info.return_type orelse
        @compileError("Property<" ++ @typeName(T) ++ "> .deinit must return void");
    if (ReturnT != void) {
        @compileError("Property<" ++ @typeName(T) ++ "> .deinit must return void, found: " ++ @typeName(ReturnT));
    }
    if (fn_info.param_types.len != 1) {
        @compileError(std.fmt.comptimePrint(
            "Property<{s}> .deinit must accept exactly one owner parameter ('*Owner'), found {d} parameters",
            .{ @typeName(T), fn_info.param_types.len },
        ));
    }
    const OwnerParam = fn_info.param_types[0].?;
    if (!isSingleItemPointer(OwnerParam)) {
        @compileError("Property<" ++ @typeName(T) ++ "> .deinit parameter must be a single-item owner pointer " ++
            "('*Owner'), found: " ++ @typeName(OwnerParam));
    }
}

/// Validates an `.init` option at declaration time.
fn validateInitializerShape(comptime T: type, comptime initializer: anytype) void {
    if (@TypeOf(initializer) != type) @compileError(
        "Property<" ++ @typeName(T) ++ "> .init must be a type produced by Init(T, func, args), found: " ++
            @typeName(@TypeOf(initializer)),
    );
    const InitializerT = initializer;
    comptime if (@typeInfo(InitializerT) != .@"struct") @compileError(
        "Property<" ++ @typeName(T) ++ "> .init must be a type produced by Init(T, func, args), found: " ++
            @typeName(InitializerT),
    );
    if (!init_mod.isInit(InitializerT)) @compileError(
        "Property<" ++ @typeName(T) ++ "> .init must be a type produced by Init(T, func, args), found: " ++
            @typeName(InitializerT),
    );
    if (InitializerT.InitFor != T) @compileError(
        "Property<" ++ @typeName(T) ++ "> .init must be produced by Init(" ++ @typeName(T) ++ ", func, args); " ++
            "found InitFor " ++ @typeName(InitializerT.InitFor),
    );
}

fn RequirePropertyField(comptime Owner: type, comptime field_name: [:0]const u8) type {
    const info = @typeInfo(Owner);
    if (info != .@"struct") @compileError("Expected struct type, found: " ++ @typeName(Owner));
    if (!@hasField(Owner, field_name)) {
        @compileError("'" ++ @typeName(Owner) ++ "' has no field named '" ++ field_name ++ "'");
    }
    const F = @FieldType(Owner, field_name);
    if (!isPropertyField(F)) {
        @compileError("'" ++ @typeName(Owner) ++ "' field '" ++ field_name ++ "' is not a Property field; " ++
            "declare it as godot.annotations.Property(T, .{ ... })");
    }
    return F;
}

fn validateGetterOwner(comptime Owner: type, comptime field_name: [:0]const u8, comptime Value: type) void {
    const F = @FieldType(Owner, field_name);
    const OwnerParam = @typeInfo(@TypeOf(@field(F.options, "get"))).@"fn".param_types[0].?;
    if (!reflect.isSelfPtrType(Owner, OwnerParam)) {
        @compileError("Property<" ++ @typeName(Value) ++ "> .get for field '" ++ field_name ++ "' on '" ++ @typeName(Owner) ++
            "' must accept '*" ++ @typeName(Owner) ++ "' or '*const " ++ @typeName(Owner) ++ "', found: " ++ @typeName(OwnerParam));
    }
}

fn validateSetterOwner(comptime Owner: type, comptime field_name: [:0]const u8) void {
    const F = @FieldType(Owner, field_name);
    const OwnerParam = @typeInfo(@TypeOf(@field(F.options, "set"))).@"fn".param_types[0].?;
    if (OwnerParam != *Owner) {
        @compileError("Property<" ++ @typeName(F.PropertyFor) ++ "> .set for field '" ++ field_name ++ "' on '" ++ @typeName(Owner) ++
            "' must accept '*" ++ @typeName(Owner) ++ "', found: " ++ @typeName(OwnerParam));
    }
}

fn validateDeinitOwner(comptime Owner: type, comptime field_name: [:0]const u8) void {
    const F = @FieldType(Owner, field_name);
    const OwnerParam = @typeInfo(@TypeOf(@field(F.options, "deinit"))).@"fn".param_types[0].?;
    if (OwnerParam != *Owner) {
        @compileError("Property<" ++ @typeName(F.PropertyFor) ++ "> .deinit for field '" ++ field_name ++ "' on '" ++ @typeName(Owner) ++
            "' must accept '*" ++ @typeName(Owner) ++ "', found: " ++ @typeName(OwnerParam));
    }
}

fn descriptorFor(comptime T: type, comptime field_name: [:0]const u8) PropertyDescriptor {
    const F = @FieldType(T, field_name);
    // Accessor shapes become checkable only once the owner type is known.
    if (comptime hasCustomGetter(F)) validateGetterOwner(T, field_name, F.PropertyFor);
    if (comptime hasCustomSetter(F)) validateSetterOwner(T, field_name);
    if (comptime hasCustomDeinit(F)) validateDeinitOwner(T, field_name);
    return comptime blk: {
        const OptionsT = @TypeOf(F.options);
        const explicit_hint = @hasField(OptionsT, "hint") or @hasField(OptionsT, "hint_string");
        var usage = F.usage;
        var hint = F.hint;
        var hint_string = F.hint_string;
        var class_name: ?[:0]const u8 = null;
        if (!explicit_hint and usageBits(usage) != 0) {
            if (property_hint.resolve(F.PropertyFor)) |resolved| {
                hint = resolved.hint;
                hint_string = resolved.hint_string;
                class_name = resolved.class_name;
            }
            if (constants.findEnumName(T, F.PropertyFor)) |registered| {
                class_name = std.fmt.comptimePrint("{s}.{s}", .{ reflect.className(T), registered.name });
                if (registered.is_bitfield) {
                    usage.class_is_bitfield = true;
                } else {
                    usage.class_is_enum = true;
                }
            }
        }
        break :blk .{
            .field_name = field_name,
            .godot_name = F.name orelse defaultGodotName(field_name),
            .value_type = F.PropertyFor,
            .usage = usage,
            .hint = hint,
            .hint_string = hint_string,
            .class_name = class_name,
            .type = F.variant_type,
        };
    };
}

fn defaultGodotName(comptime field_name: [:0]const u8) [:0]const u8 {
    return naming.comptimeConvert(.godot, .property, field_name);
}

pub fn usageBits(comptime flags: enums.PropertyUsageFlags) u32 {
    return @bitCast(flags);
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;
const naming = @import("naming");

const builtins = @import("../builtins/builtins.zig");
const enums = @import("../enums.zig");
const ownership = @import("../ownership.zig");
const reflect = @import("../reflect/reflect.zig");
const constants = @import("constants.zig");
const init_mod = @import("init.zig");
const marker_kind = @import("marker.zig");
const property_hint = @import("property_hint.zig");
