//! `Property` field annotation: wrapper type, option normalization, accessors,
//! discovery, and lifetime helpers. See docs/properties.md.

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
        pub const has_custom_set = @hasField(@TypeOf(p_options), "set");
        pub const has_custom_init = @hasField(@TypeOf(p_options), "init");
        pub const has_custom_deinit = @hasField(@TypeOf(p_options), "deinit");
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

/// Comptime metadata for one `Property` field.
pub const PropertyDescriptor = struct {
    field_name: [:0]const u8,
    godot_name: [:0]const u8,
    value_type: type,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    type: ?interface.VariantType,
};

/// Finds `Property` fields declared directly on `T`, in declaration order.
pub fn findPropertyFieldNames(comptime T: type) []const [:0]const u8 {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") @compileError("Expected struct type, found: " ++ @typeName(T));
        const info = type_info.@"struct";
        var names: [info.field_names.len][:0]const u8 = undefined;
        var n: usize = 0;
        for (info.field_names, info.field_types) |name, F| {
            if (!reflect.isNormalStruct(F)) continue;
            if (!marker_kind.is(F, .property)) continue;
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

/// Setter thunk, or null when `.read_only`. The default setter owns managed
/// builtin replacement and `RefCounted` retain/release.
pub fn setterFn(comptime Owner: type, comptime field_name: [:0]const u8) ?fn (*Owner, PropertyValueType(@FieldType(Owner, field_name))) void {
    const F = RequirePropertyField(Owner, field_name);
    const Value = F.PropertyFor;
    if (comptime F.read_only) return null;
    if (comptime hasCustomSetter(F)) {
        validateSetterOwner(Owner, field_name);
        const set = @field(F.options, "set");
        return set;
    }
    return struct {
        fn setValue(owner: *Owner, value: Value) void {
            const field = &@field(owner, field_name).value;

            // The default setter is the one place that replaces a managed
            // value. Keep its ownership policy here so every caller gets the
            // same behavior as engine dispatch.
            if (comptime isKnownManagedBuiltin(Value) or Value == builtins.Variant) {
                field.deinit();
            } else if (comptime reflect.isRefCountedPointer(Value)) {
                // Take the new reference first: assigning the current object
                // back must not release the last reference before retaining it.
                retainRefCounted(Value, value);
                releaseRefCounted(Value, field.*);
            }

            field.* = value;
        }
    }.setValue;
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

/// Custom `.deinit` thunk, or null.
pub fn deinitFn(comptime Owner: type, comptime field_name: [:0]const u8) ?fn (*Owner) void {
    const F = RequirePropertyField(Owner, field_name);
    if (comptime !hasCustomDeinit(F)) return null;
    validateDeinitOwner(Owner, field_name);
    const deinit_hook = @field(F.options, "deinit");
    return deinit_hook;
}

/// Best-effort cleanup of every `Property` field: custom `.deinit`, value
/// `deinit`, or `RefCounted` release. Fields must be valid; does not free the
/// instance.
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
    if (comptime hasCustomDeinit(F)) {
        deinitFn(T, field_name).?(instance);
        return;
    }
    const field = &@field(instance, field_name).value;
    if (comptime hasValueDeinit(Value)) {
        field.deinit();
        return;
    }
    if (comptime reflect.isRefCountedPointer(Value)) {
        releaseRefCounted(Value, field.*);
    }
}

/// True when `T` is a struct value type declaring `deinit`.
fn hasValueDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "deinit"),
        else => false,
    };
}

/// True for builtins with engine-owned storage and a `deinit` contract.
pub fn isKnownManagedBuiltin(comptime T: type) bool {
    return bindings.builtins.traits.isManagedBuiltin(T);
}

/// Takes a reference on a `RefCounted` pointer value; null optionals are a
/// no-op and non-`RefCounted` types are a compile error.
pub fn retainRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    _ = classes.core.RefCounted.reference(object);
}

/// Releases a reference taken by `retainRefCounted`.
pub fn releaseRefCounted(comptime Value: type, value: Value) void {
    const object = refCountedObject(Value, value) orelse return;
    _ = classes.core.RefCounted.unreference(object);
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

const NormalizedOptions = struct {
    name: ?[:0]const u8,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    variant_type: ?interface.VariantType,
    read_only: bool,
};

const option_keys = [_][]const u8{ "usage", "name", "hint", "hint_string", "type", "get", "set", "read_only", "init", "deinit" };

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
                "Property<{s}> has unknown option '.{s}'. Supported options: .usage, .name, .hint, .hint_string, .type, .get, .set, .read_only, .init, .deinit.",
                .{ @typeName(T), key },
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
    if (@hasField(OptionsT, "set")) validateSetterShape(T, options.set);
    if (@hasField(OptionsT, "deinit")) validateDeinitShape(T, options.deinit);
    const read_only: bool = if (@hasField(OptionsT, "read_only")) blk: {
        if (@TypeOf(options.read_only) != bool) @compileError(
            "Property<" ++ @typeName(T) ++ "> .read_only must be a bool, found: " ++ @typeName(@TypeOf(options.read_only)),
        );
        break :blk options.read_only;
    } else false;
    if (@hasField(OptionsT, "set") and read_only) {
        @compileError("Property<" ++ @typeName(T) ++ "> cannot combine '.read_only = true' with a custom '.set'; " ++
            "a read-only property has no engine setter. Remove one of them.");
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
    return .{
        .field_name = field_name,
        .godot_name = F.name orelse defaultGodotName(field_name),
        .value_type = F.PropertyFor,
        .usage = F.usage,
        .hint = F.hint,
        .hint_string = F.hint_string,
        .type = F.variant_type,
    };
}

fn defaultGodotName(comptime field_name: [:0]const u8) [:0]const u8 {
    return naming.comptimeConvert(.godot, .property, field_name);
}

// Compile-time coverage. These checks are analyzed on every build that analyzes
// annotations; `annotations.zig` calls `comptimeSelfCheck()` so the registration
// backend does not have to import Property first.
//
// A duplicate engine name is a compile error and therefore cannot be exercised
// here; `descriptors` reports it with both conflicting field names. The
// `.read_only = true` + custom `.set` conflict and malformed `.init` initializers
// (not an `Init` type, or a mismatched `InitFor`) are compile errors for the same
// reason; `normalizeOptions` reports them.

const UsageOwner = struct {
    from_literal: Property(u32, .{ .usage = .none }) = .init(0),
    from_flags: Property(u32, .{ .usage = .{ .storage = true } }) = .init(0),
    from_value: Property(u32, .{ .usage = .default }) = .init(0),
};

const VariantTypeOwner = struct {
    literal: Property(u32, .{ .usage = .none, .type = .string }) = .init(0),
    explicit: Property(f32, .{ .usage = .none, .type = interface.VariantType.float }) = .init(0),
    automatic: Property(u32, .{ .usage = .none }) = .init(0),
};

const CheckOwner = struct {
    plain: u32 = 0,
    count: Property(u32, .{ .usage = .none }) = .init(0),
    health: Property(i32, .{
        .usage = .{ .storage = true, .editor = true },
        .hint = .range,
        .hint_string = "0,100",
        .name = "Health",
        .get = getHealth,
        .set = setHealth,
    }) = .init(100),
    ratio: Property(f32, .{
        .usage = .default,
        .get = getRatio,
    }) = .init(1.0),
    tag: Property(u32, .{ .usage = .{ .storage = true } }) = .init(0),

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
    healthBar: Property(u32, .{ .usage = .exported }) = .init(0),
};

/// A custom setter without a getter keeps the default getter.
const SetterOnlyOwner = struct {
    value: Property(u32, .{ .usage = .none, .set = set }) = .init(1),

    fn set(self: *@This(), stored: u32) void {
        self.value.value = stored + 1;
    }
};

/// `.read_only` rejects engine sets but does not change usage flags.
const ReadOnlyOwner = struct {
    sealed: Property(u32, .{
        .usage = .exported,
        .read_only = true,
    }) = .init(9),
    computed: Property(f32, .{
        .usage = .none,
        .read_only = true,
        .get = getComputed,
    }) = .init(1.5),
    writable: Property(u32, .{
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
    node: OnReadyAnnotation(classes.core.Node).Node("./ChildNode"),
    lookalike: Lookalike = .{},
    health: Property(i32, .{ .usage = .exported }) = .init(0),
};

const OnReadyAnnotation = on_ready.OnReady;

/// Holder-owned user value type.
const DeinitProbe = struct {
    deinit_called: bool = false,
    hook_called: bool = false,

    pub fn deinit(self: *@This()) void {
        self.deinit_called = true;
    }
};

/// Custom `.deinit` overrides automatic value cleanup.
const HookOwner = struct {
    probe: Property(DeinitProbe, .{
        .usage = .none,
        .deinit = deinitProbe,
    }) = .init(.{}),
    plain: Property(u32, .{
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

/// Automatic cleanup applies even with custom accessors.
const FieldLifetimeOwner = struct {
    plain: Property(u32, .{ .usage = .none }) = .init(0),
    probe: Property(DeinitProbe, .{ .usage = .none }) = .init(.{}),
    accessor: Property(DeinitProbe, .{
        .usage = .none,
        .get = getAccessor,
        .set = setAccessor,
    }) = .init(.{}),

    fn getAccessor(self: *const @This()) DeinitProbe {
        return self.accessor.value;
    }

    fn setAccessor(self: *@This(), value: DeinitProbe) void {
        self.accessor.value = value;
    }
};

/// Extension over `RefCounted`; helpers resolve the engine base.
const RefCountedExtension = struct {
    pub const Extends = classes.core.RefCounted;
    base: annotation_base.Base(Extends) = .{},
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
    plain: Property(u32, .{ .usage = .none }) = .init(11),
    count: Property(u32, .{
        .usage = .none,
        .init = init_mod.Init(u32, initialCount, .{}),
    }) = .init(0),
    doubled: Property(u32, .{
        .usage = .none,
        .init = init_mod.Init(u32, initialDoubled, .{.{ .field = "seed" }}),
    }) = .init(0),
    owned: Property(u32, .{
        .usage = .none,
        .init = init_mod.Init(u32, initialFromOwner, .{.owner}),
    }) = .init(0),
    based: Property(u32, .{
        .usage = .none,
        .init = init_mod.Init(u32, initialFromBase, .{.base}),
    }) = .init(0),
    shorthand: Property(u32, .{ .usage = .none }).Init(
        initialDoubled,
        .{.{ .field = "seed" }},
    ) = .init(0),
};

/// Compile-only `.init` coverage; engine paths are analyzed, not executed.
const BuiltinInitializerOwner = struct {
    name: Property(builtins.StringName, .{
        .usage = .none,
        .init = init_mod.Init(builtins.StringName, .fromLatin1, .{ "probe", false }),
    }) = .init(undefined),
    count: Property(u32, .{
        .usage = .none,
        .init = init_mod.Init(u32, initialCount, .{}),
    }) = .init(0),
};

/// Compile-only `Variant` ownership coverage.
const VariantValueOwner = struct {
    value: Property(builtins.Variant, .{ .usage = .none, .type = .string }) = .init(builtins.Variant.nil),
};

/// Compile-only ownership coverage; engine calls are not executed.
const RefLifetimeOwner = struct {
    engine: Property(?*classes.core.RefCounted, .{ .usage = .none }) = .init(null),
    engine_const: Property(*const classes.core.RefCounted, .{ .usage = .none }) = .init(undefined),
    extension: Property(?*RefCountedExtension, .{ .usage = .none }) = .init(null),
    extension_const: Property(*const RefCountedExtension, .{ .usage = .none }) = .init(undefined),
    node: Property(?*classes.core.Node, .{ .usage = .none }) = .init(null),
};

pub fn usageBits(comptime flags: enums.PropertyUsageFlags) u32 {
    return @bitCast(flags);
}

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("property.zig: " ++ message);
}

fn checkVariantValueProperty() void {
    const set = setterFn(VariantValueOwner, "value") orelse @compileError("Variant value property must have a setter");
    _ = set;
    const desc = descriptors(VariantValueOwner)[0];
    check(desc.type == .string, "Variant value property must use the explicit type override");
}

fn checkUsageNormalization() void {
    check(usageBits(enums.PropertyUsageFlags.none) == 0, ".none must be zero flags");
    check(usageBits(enums.PropertyUsageFlags.default) == 6, ".default must be PROPERTY_USAGE_DEFAULT (storage + editor)");
    check(usageBits(enums.PropertyUsageFlags.exported) == 6, ".exported must be storage + editor");

    const usage_descs = descriptors(UsageOwner);
    check(usageBits(usage_descs[0].usage) == 0, "'.usage = .none' must normalize to zero flags");
    check(usageBits(usage_descs[1].usage) == 2, "anonymous flag structs must normalize into PropertyUsageFlags");
    check(usageBits(usage_descs[2].usage) == 6, "PropertyUsageFlags values must pass through unchanged");
}

fn checkVariantTypeOverride() void {
    const descs = descriptors(VariantTypeOwner);
    check(descs[0].type == .string, ".type enum literal must normalize");
    check(descs[1].type == .float, "interface.VariantType value must pass through");
    check(descs[2].type == null, "omitted .type must stay automatic");
    check(@FieldType(VariantTypeOwner, "literal").variant_type == .string, "wrapper must expose normalized variant_type");
}

fn checkDiscovery() void {
    const names = findPropertyFieldNames(CheckOwner);
    check(names.len == 4, "findPropertyFieldNames must collect only Property fields, in declaration order");
    check(std.mem.eql(u8, names[0], "count"), "findPropertyFieldNames must keep declaration order (1)");
    check(std.mem.eql(u8, names[1], "health"), "findPropertyFieldNames must keep declaration order (2)");
    check(std.mem.eql(u8, names[2], "ratio"), "findPropertyFieldNames must keep declaration order (3)");
    check(std.mem.eql(u8, names[3], "tag"), "findPropertyFieldNames must keep declaration order (4)");

    check(findPropertyFieldNames(NoProperties).len == 0, "classes without Property fields must report no properties");
    check(findPropertyFieldNames(Lookalike).len == 0, "a lookalike isSelf must not be discovered"); // Lookalike itself has no Property field
    check(isPropertyField(@FieldType(CheckOwner, "health")), "Property wrappers must identify themselves");
    check(!isPropertyField(u32), "scalars are not Property wrappers");
    check(!isPropertyField(@FieldType(CheckOwner, "plain")), "plain fields are not Property wrappers");
    check(!isPropertyField(Lookalike), "a lookalike isSelf is not a Property wrapper");
}

fn checkDescriptors() void {
    const descs = descriptors(CheckOwner);
    check(descs.len == 4, "descriptors must cover every discovered field");
    check(std.mem.eql(u8, descs[0].field_name, "count"), "descriptor field_name must be the Zig field name");
    check(descs[0].value_type == u32, "descriptor value_type must be the wrapper PropertyFor");
    check(std.mem.eql(u8, descs[0].godot_name, "count"), "default engine name must come from the field name");
    check(std.mem.eql(u8, descs[1].godot_name, "Health"), "explicit '.name' must be used verbatim");
    check(descs[1].value_type == i32, "descriptor value_type must follow the field");
    check(descs[1].hint == enums.PropertyHint.range, "'.hint = .range' must normalize to PropertyHint.range");
    check(std.mem.eql(u8, descs[1].hint_string, "0,100"), "hint_string must keep the declared bytes");
    check(descs[1].hint_string[descs[1].hint_string.len] == 0, "hint_string must be sentinel-terminated");
    check(usageBits(descs[1].usage) == usageBits(enums.PropertyUsageFlags.exported), "anonymous flag struct must equal the exported preset");
    check(descs[2].hint == .none, "omitted hints default to .none");
    check(descs[2].hint_string.len == 0, "omitted hint strings default to empty");
    check(descs[2].hint_string[0] == 0, "omitted hint strings must still be sentinel-terminated");
    check(usageBits(descs[3].usage) == 2, "single anonymous flag must normalize");

    const naming_descs = descriptors(NamingOwner);
    check(std.mem.eql(u8, naming_descs[0].godot_name, "health_bar"), "default engine names must use naming.comptimeConvert");
}

fn checkAccessors() void {
    const Health = @FieldType(CheckOwner, "health");
    check(hasCustomGetter(Health), "custom .get must be detected");
    check(hasCustomSetter(Health), "custom .set must be detected");
    check(!hasCustomGetter(@FieldType(CheckOwner, "count")), "properties without .get must report no custom getter");
    check(!hasCustomSetter(@FieldType(CheckOwner, "count")), "properties without .set must report no custom setter");
    check(hasCustomGetter(@FieldType(CheckOwner, "ratio")), "const getters must be detected");

    const health_getter = getterFn(CheckOwner, "health");
    const health_setter = setterFn(CheckOwner, "health") orelse @compileError("property.zig: custom setter must be discovered");
    check(@TypeOf(health_getter) == fn (*CheckOwner) i32, "custom getter thunk must take a mutable owner pointer");
    check(@TypeOf(health_setter) == fn (*CheckOwner, i32) void, "custom setter thunk must match the accessor shape");
    check(isWritable(CheckOwner, "health"), "custom setter properties are writable");
    check(isWritable(CheckOwner, "count"), "stored-value properties are writable by default");
    check(isWritable(CheckOwner, "ratio"), "custom getters without setters use the default write");
    check(setterFn(CheckOwner, "ratio") != null, "custom getters without setters expose the default setter");
    check(@TypeOf(getterFn(CheckOwner, "ratio")) == fn (*CheckOwner) f32, "const getters must be callable through a mutable owner");
    check(@TypeOf(getterFn(CheckOwner, "count")) == fn (*CheckOwner) u32, "default getters use the owner pointer");

    const setter_only = @FieldType(SetterOnlyOwner, "value");
    check(!hasCustomGetter(setter_only), "setter-only properties keep the default getter");
    check(hasCustomSetter(setter_only), "setter-only properties must report their custom setter");
    check(isWritable(SetterOnlyOwner, "value"), "setter-only properties are writable");
    var setter_only_owner: SetterOnlyOwner = .{};
    check(getterFn(SetterOnlyOwner, "value")(&setter_only_owner) == 1, "setter-only properties read the stored value");
    setterFn(SetterOnlyOwner, "value").?(&setter_only_owner, 41);
    check(getterFn(SetterOnlyOwner, "value")(&setter_only_owner) == 42, "setter-only properties call the custom setter");

    var owner: CheckOwner = .{};
    check(health_getter(&owner) == 100, "default field values must be readable through the accessor");
    health_setter(&owner, 7);
    check(health_getter(&owner) == 7, "custom accessors must see the same stored value");
    setterFn(CheckOwner, "count").?(&owner, 3);
    check(getterFn(CheckOwner, "count")(&owner) == 3, "default setter must write the stored value");
    setterFn(CheckOwner, "ratio").?(&owner, 2.5);
    check(getterFn(CheckOwner, "ratio")(&owner) == 2.5, "default setter must write .value behind a custom getter");

    const Wrapper = Property(i32, .{ .usage = .exported });
    var wrapper: Wrapper = .init(5);
    check(wrapper.get() == 5, "Property.get must read the stored value");
    wrapper.set(9);
    check(wrapper.get() == 9, "Property.set must write the stored value");
    check(Wrapper.PropertyFor == i32, "PropertyFor must expose the value type");
    check(usageBits(Wrapper.usage) == usageBits(enums.PropertyUsageFlags.exported), "wrapper options must be normalized");
    check(Wrapper.marker == marker_kind.Kind.property, "Property wrappers must declare marker.Kind.property");
}

fn checkReadOnly() void {
    const sealed = @FieldType(ReadOnlyOwner, "sealed");
    check(sealed.read_only, "read_only must be exposed on the wrapper");
    check(!sealed.has_custom_get, ".read_only must keep the default getter");
    check(!sealed.has_custom_set, ".read_only must not declare a custom setter");
    check(isReadOnly(ReadOnlyOwner, "sealed"), ".read_only properties must reject engine set dispatch");
    check(!isWritable(ReadOnlyOwner, "sealed"), ".read_only properties must not be writable");
    check(setterFn(ReadOnlyOwner, "sealed") == null, ".read_only properties expose no setter");

    var owner: ReadOnlyOwner = .{};
    check(getterFn(ReadOnlyOwner, "sealed")(&owner) == 9, ".read_only properties keep the default getter");
    check(getterFn(ReadOnlyOwner, "computed")(&owner) == 1.5, "read-only properties keep their custom getter");

    check(isReadOnly(ReadOnlyOwner, "computed"), "explicit .read_only must reject the default setter");
    check(setterFn(ReadOnlyOwner, "computed") == null, "explicit .read_only exposes no setter");

    const writable = @FieldType(ReadOnlyOwner, "writable");
    check(!writable.read_only, "read_only must normalize an explicit false");
    check(isWritable(ReadOnlyOwner, "writable"), "explicit read_only = false must keep a custom setter writable");
    setterFn(ReadOnlyOwner, "writable").?(&owner, 4);
    check(owner.writable.value == 4, "explicit read_only = false must dispatch the custom setter");

    // Usage flags are untouched: `.read_only` is dispatch policy, not inspector
    // metadata. The inspector flag stays an explicit usage flag.
    const descs = descriptors(ReadOnlyOwner);
    check(descs.len == 3, "read-only checks must cover every Property field");
    check(usageBits(descs[0].usage) == usageBits(enums.PropertyUsageFlags.exported), ".read_only must not change usage flags");
    const inspector_read_only = usageBits(.{ .read_only = true });
    check((usageBits(descs[0].usage) & inspector_read_only) == 0, ".read_only must not imply PropertyUsageFlags.read_only");
}

fn checkInitializers() void {
    const count = @FieldType(InitializerOwner, "count");
    check(count.has_custom_init, "has_custom_init must mirror the option");
    check(hasCustomInitializer(count), "hasCustomInitializer must detect a declared .init");
    check(!hasCustomInitializer(@FieldType(InitializerOwner, "plain")), "fields without .init must report no custom initializer");
    check(!count.has_custom_get and !count.has_custom_set, ".init is creation-time only and not an engine accessor");

    // Eager creation-time assignment: replace ordinary field defaults with the
    // initializer results, resolving every placeholder form.
    var owner: InitializerOwner = .{};
    var base: InitializerBase = .{};
    initPropertyFields(InitializerOwner, InitializerBase, &owner, &base);
    check(owner.count.value == 40, ".init initializer results must be assigned eagerly");
    check(owner.doubled.value == 10, ".init 'field' arguments must resolve owner fields");
    check(owner.owned.value == 6, ".init 'owner' arguments must pass the owner pointer");
    check(owner.based.value == 3, ".init 'base' arguments must pass the base pointer");
    check(owner.shorthand.value == 10, ".Init(...) shorthand must add the same eager initializer");
    check(hasCustomInitializer(@FieldType(InitializerOwner, "shorthand")), ".Init(...) shorthand must expose the initializer");
    check(owner.plain.value == 11, "initPropertyFields must leave fields without .init alone");

    var no_props: NoProperties = .{};
    var dummy_base: void = {};
    initPropertyFields(NoProperties, void, &no_props, &dummy_base);
    check(no_props.value == 0, "initPropertyFields must ignore classes without Property fields");
}

fn checkMarkerIdentity() void {
    check(marker_kind.is(@FieldType(CheckOwner, "health"), .property), "Property marker kind must be property");
    check(!marker_kind.is(@FieldType(CheckOwner, "health"), .on_ready), "Property marker must not read as OnReady");
    check(!marker_kind.is(@FieldType(CheckOwner, "health"), .base), "Property marker must not read as Base");

    const mixed_props = findPropertyFieldNames(MixedOwner);
    const mixed_on_ready = on_ready.findOnReadyFieldNames(MixedOwner);
    check(mixed_props.len == 1, "mixed classes must report exactly their Property fields");
    check(std.mem.eql(u8, mixed_props[0], "health"), "mixed classes must not report OnReady fields as properties");
    check(mixed_on_ready.len == 1, "mixed classes must report exactly their OnReady fields");
    check(std.mem.eql(u8, mixed_on_ready[0], "node"), "mixed classes must not report Property fields as OnReady");
    check(!isPropertyField(@FieldType(MixedOwner, "node")), "OnReady wrappers are not Property fields");
    check(!marker_kind.is(@FieldType(MixedOwner, "lookalike"), .property), "lookalikes must not declare a marker");
}

fn checkLifetime() void {
    // Custom `.deinit` hooks: detected, callable, and validated through
    // `descriptors` once the owning class is known.
    const hooked = @FieldType(HookOwner, "probe");
    check(hasCustomDeinit(hooked), "custom .deinit must be detected");
    check(hooked.has_custom_deinit, "has_custom_deinit must mirror the option");
    check(!hasCustomDeinit(@FieldType(FieldLifetimeOwner, "probe")), "fields without .deinit report no custom deinit");
    const hook_fn = deinitFn(HookOwner, "probe") orelse @compileError("property.zig: custom .deinit must be discoverable");
    check(@TypeOf(hook_fn) == fn (*HookOwner) void, "custom .deinit thunk must take a mutable owner pointer");
    check(deinitFn(FieldLifetimeOwner, "probe") == null, "fields without .deinit expose no custom deinit hook");
    _ = descriptors(HookOwner);

    // Custom hook overrides the automatic value cleanup.
    var hook_owner: HookOwner = .{};
    deinitPropertyFields(HookOwner, &hook_owner);
    check(hook_owner.probe.value.hook_called, "custom .deinit must run");
    check(!hook_owner.probe.value.deinit_called, "custom .deinit must override the automatic value cleanup");
    check(hook_owner.plain_deinit_called, "custom .deinit must run for any value type");

    // Automatic cleanup: value types with `deinit`, independent of accessors.
    var field_owner: FieldLifetimeOwner = .{};
    deinitPropertyFields(FieldLifetimeOwner, &field_owner);
    check(field_owner.probe.value.deinit_called, "struct value types declaring deinit must be deinitialized");
    check(field_owner.accessor.value.deinit_called, "custom accessors must not skip automatic cleanup");

    // Non-property fields and classes without Property fields are no-ops.
    var no_props: NoProperties = .{};
    deinitPropertyFields(NoProperties, &no_props);
    check(no_props.value == 0, "deinitPropertyFields must ignore non-property fields");

    // The managed-builtin allow-list is explicit and does not accept arbitrary
    // structs, even ones declaring `deinit`.
    check(isKnownManagedBuiltin(builtins.String), "String must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.StringName), "StringName must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.NodePath), "NodePath must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.Callable), "Callable must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.Signal), "Signal must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.Array), "Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.Dictionary), "Dictionary must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedByteArray), "PackedByteArray must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedColorArray), "PackedColorArray must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedFloat32Array), "PackedFloat32Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedFloat64Array), "PackedFloat64Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedInt32Array), "PackedInt32Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedInt64Array), "PackedInt64Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedStringArray), "PackedStringArray must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedVector2Array), "PackedVector2Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedVector3Array), "PackedVector3Array must be a known managed builtin");
    check(isKnownManagedBuiltin(builtins.PackedVector4Array), "PackedVector4Array must be a known managed builtin");
    check(!isKnownManagedBuiltin(builtins.Vector2), "plain value builtins are not managed builtins");
    check(!isKnownManagedBuiltin(builtins.Variant), "Variant is not a managed builtin");
    check(!isKnownManagedBuiltin(u32), "scalars are not managed builtins");
    check(!isKnownManagedBuiltin(DeinitProbe), "arbitrary structs are not known managed builtins");
    check(!isKnownManagedBuiltin(?*classes.core.RefCounted), "RefCounted pointers are managed by references, not deinit");
}

/// Compile-only ownership coverage.
fn checkOwnershipRuntimePaths() void {
    retainRefCounted(?*classes.core.RefCounted, null);
    releaseRefCounted(?*const classes.core.RefCounted, null);
    retainRefCounted(*const RefCountedExtension, undefined);
    releaseRefCounted(*RefCountedExtension, undefined);

    var owner: RefLifetimeOwner = .{};
    deinitPropertyFields(RefLifetimeOwner, &owner);
}

/// Compile-only `.init` coverage.
fn checkInitializerEnginePaths() void {
    var owner: BuiltinInitializerOwner = .{};
    var dummy_base: void = {};
    initPropertyFields(BuiltinInitializerOwner, void, &owner, &dummy_base);
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
}

comptime {
    comptimeChecks();
    _ = &checkOwnershipRuntimePaths;
    _ = &checkInitializerEnginePaths;
}

/// Runs this module's compile-only checks.
pub fn comptimeSelfCheck() void {
    comptime comptimeChecks();
    _ = &checkOwnershipRuntimePaths;
    _ = &checkInitializerEnginePaths;
}

const std = @import("std");
const bindings = @import("bindings");
const interface = bindings.interface;
const naming = @import("naming");

const enums = @import("../enums.zig");

const reflect = @import("../reflect/reflect.zig");

const builtins = @import("../builtins/builtins.zig");

const classes = @import("../classes/classes.zig");

const annotation_base = @import("base.zig");

const init_mod = @import("init.zig");

const on_ready = @import("on_ready.zig");

const marker_kind = @import("marker.zig");
