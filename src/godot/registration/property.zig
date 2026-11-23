//! Dynamic property backend: turns `annotations.Property` descriptors and the
//! `PropertyGroups` layout into the `ClassCreationInfo6` callbacks.
//! See docs/properties.md.

/// The engine callbacks installed on `ClassCreationInfo6` for one class.
pub const Callbacks = struct {
    set_func: interface.ClassSet = null,
    get_func: interface.ClassGet = null,
    get_property_list_func: interface.ClassGetPropertyList = null,
    free_property_list_func: interface.ClassFreePropertyList2 = null,
};

/// True when `T` declares at least one `Property` field.
pub fn hasPropertyFields(comptime T: type) bool {
    return comptime property.findPropertyFieldNames(T).len != 0;
}

/// Number of entries emitted by `get_property_list`: one per section header
/// plus one per visible descriptor (`usage != 0`), in `property.layout` order.
pub fn propertyEntryCount(comptime T: type) usize {
    return comptime property.layout(T).len;
}

/// Forces Variant-type validation for every descriptor, including hidden ones.
fn validateDescriptors(comptime T: type) void {
    inline for (property.descriptors(T)) |desc| {
        conversion.checkSupported(
            desc.value_type,
            .variant,
            std.fmt.comptimePrint("Property '{s}.{s}'", .{ @typeName(T), desc.field_name }),
        );
        _ = requiredVariantType(T, desc);
    }
}

/// Builds the dynamic property callbacks for `T`.
pub fn callbacks(comptime T: type) Callbacks {
    if (comptime !hasPropertyFields(T)) return .{};

    // Hidden descriptors have no list entry but still need a storable Variant
    // type; validate every descriptor before building callbacks.
    comptime validateDescriptors(T);

    const list_visible = comptime propertyEntryCount(T) != 0;
    return .{
        .set_func = SetCallback(T),
        .get_func = GetCallback(T),
        .get_property_list_func = if (comptime list_visible) GetPropertyListCallback(T) else null,
        .free_property_list_func = if (comptime list_visible) free_property_list else null,
    };
}

/// Process-lifetime `PropertyInfo` table for the property-list layout, in order.
pub fn propertyInfoList(comptime T: type) []const interface.PropertyInfo {
    const entry_count = comptime propertyEntryCount(T);
    if (comptime entry_count == 0) return &.{};

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
    const value = conversion.decodeVariant(Value, variant) orelse return false;
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
    conversion.encodeVariant(Value, getter(instance), result);
    return true;
}

fn ListStorage(comptime T: type) type {
    const entry_count = comptime property.layout(T).len;
    return struct {
        var names: [entry_count]builtins.StringName = undefined;
        var class_names: [entry_count]builtins.StringName = undefined;
        var hint_strings: [entry_count]builtins.String = undefined;
        var infos: [entry_count]interface.PropertyInfo = undefined;
        var initialized: bool = false;
    };
}

fn initList(comptime T: type) void {
    const Storage = ListStorage(T);
    const descs = comptime property.descriptors(T);
    const entries = comptime property.layout(T);

    inline for (entries, 0..) |entry, slot| {
        switch (entry) {
            .section => |section| {
                // Section headers carry no value: NIL type, no hint, and exactly
                // one group bit. They never reach set/get.
                Storage.names[slot] = builtins.StringName.fromComptimeLatin1(section.name);
                Storage.class_names[slot] = builtins.StringName.fromComptimeLatin1("");
                Storage.hint_strings[slot] = builtins.String.fromComptimeLatin1(sectionHintString(section));
                Storage.infos[slot] = .{
                    .type = .nil,
                    .name = @as(interface.StringNamePtr, @ptrCast(&Storage.names[slot])),
                    .class_name = @as(interface.StringNamePtr, @ptrCast(&Storage.class_names[slot])),
                    .hint = @backingInt(enums.PropertyHint.none),
                    .hint_string = @as(interface.StringPtr, @ptrCast(&Storage.hint_strings[slot])),
                    .usage = property.usageBits(sectionUsage(section)),
                };
            },
            .field => |desc_index| {
                const desc = comptime descs[desc_index];
                const class_name = comptime propertyClassName(desc);
                Storage.names[slot] = builtins.StringName.fromComptimeLatin1(desc.godot_name);
                Storage.class_names[slot] = builtins.StringName.fromComptimeLatin1(class_name);
                Storage.hint_strings[slot] = builtins.String.fromComptimeLatin1(desc.hint_string);
                Storage.infos[slot] = .{
                    .type = requiredVariantType(T, desc),
                    .name = @as(interface.StringNamePtr, @ptrCast(&Storage.names[slot])),
                    .class_name = @as(interface.StringNamePtr, @ptrCast(&Storage.class_names[slot])),
                    .hint = @backingInt(desc.hint),
                    .hint_string = @as(interface.StringPtr, @ptrCast(&Storage.hint_strings[slot])),
                    .usage = property.usageBits(desc.usage),
                };
            },
        }
    }
}

/// `PropertyGroups` depth hint: empty for a top-level group, `",<depth>"` for a
/// subgroup (for example `",1"`). See docs/properties.md.
fn sectionHintString(comptime section: property.Section) [:0]const u8 {
    if (section.depth == 0) return "";
    return std.fmt.comptimePrint(",{d}", .{section.depth});
}

/// Section usage is exactly one group bit: `PROPERTY_USAGE_GROUP` at depth 0,
/// `PROPERTY_USAGE_SUBGROUP` above it.
fn sectionUsage(comptime section: property.Section) enums.PropertyUsageFlags {
    return if (section.depth == 0) .{ .group = true } else .{ .subgroup = true };
}

/// Variant type for a property value, or a compile error when unsupported.
fn requiredVariantType(
    comptime T: type,
    comptime desc: property.PropertyDescriptor,
) interface.VariantType {
    if (desc.type) |variant_type| return variant_type;
    return comptime conversion.variantType(desc.value_type) orelse {
        if (desc.value_type == builtins.Variant) @compileError(std.fmt.comptimePrint(
            "Property '{s}.{s}' stores Variant transparently; add an explicit '.type = ...'.",
            .{ @typeName(T), desc.field_name },
        ));
        @compileError(std.fmt.comptimePrint(
            "Property '{s}.{s}' has no Variant type for declared type '{s}'. " ++
                "Declare a custom Conversion marker for the type.",
            .{ @typeName(T), desc.field_name, @typeName(desc.value_type) },
        ));
    };
}

/// Engine class name for a property-list entry: an explicit descriptor override
/// wins, otherwise use the class behind the converter's engine type.
fn propertyClassName(comptime desc: property.PropertyDescriptor) [:0]const u8 {
    if (desc.class_name) |class_name| return class_name;
    return comptime conversion.engineClassName(desc.value_type);
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const property = @import("../annotations/property.zig");
const builtins = @import("../builtins/builtins.zig");
const conversion = @import("../conversion.zig");
const enums = @import("../enums.zig");
