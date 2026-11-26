//! Declared property type -> engine hint metadata. See docs/properties.md.

/// Engine hint metadata resolved from a property's declared Zig type.
pub const Resolved = struct {
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    /// Engine class name for object pointers; null for enums/bitfields and
    /// builtins that have no hint.
    class_name: ?[:0]const u8,
};

/// A declared container shape detected from a conversion type: the engine
/// container kind plus the element or key/value types declared on the type.
pub const DeclaredContainer = union(enum) {
    array: struct {
        element: type,
    },
    dictionary: struct {
        key: ?type,
        value: ?type,
    },
};

/// Resolves a declared property value type to an engine hint.
///
/// Enums and bitpack structs resolve from the Zig declaration alone. Object
/// pointers get a node/resource picker hint when the class inherits `Node` or
/// `Resource`, otherwise no hint but still a class name. Plain builtins return
/// null. Registered enums add their class name and usage bits separately, in
/// `annotations/property.zig`.
pub fn resolve(comptime T: type) ?Resolved {
    comptime {
        if (constants.typeHint(T)) |type_hint| {
            return .{
                .hint = if (type_hint.is_bitfield) .flags else .@"enum",
                .hint_string = type_hint.hint_string,
                .class_name = null,
            };
        }

        if (reflect.objectTarget(T)) |target| {
            const class_name = reflect.classNameOf(T);
            if (reflect.isNodeClass(target.class)) {
                return .{
                    .hint = .node_type,
                    .hint_string = class_name,
                    .class_name = class_name,
                };
            }
            if (reflect.isResourceClass(target.class)) {
                return .{
                    .hint = .resource_type,
                    .hint_string = class_name,
                    .class_name = class_name,
                };
            }
            return .{
                .hint = .none,
                .hint_string = "",
                .class_name = class_name,
            };
        }

        return null;
    }
}

/// Resolves a converter's engine object representation to the hint its object
/// pointer would get (e.g. `godot.ownership.Ref(Resource)`); direct types
/// return null because `resolve` already covers them.
pub fn resolveConverted(comptime T: type) ?Resolved {
    comptime {
        const Engine = conversion.engineType(T) orelse return null;
        if (Engine == T) return null;
        return resolve(Engine);
    }
}

/// Resolves a typed `Array` element to `PROPERTY_HINT_ARRAY_TYPE` metadata; a
/// `Variant` element is untyped and yields no hint.
pub fn resolveArray(comptime Element: type) ?Resolved {
    comptime {
        const spec = sideSpec(Element) orelse return null;
        return .{
            .hint = .array_type,
            .hint_string = spec.format(),
            .class_name = null,
        };
    }
}

/// Resolves typed `Dictionary` key/value sides to
/// `PROPERTY_HINT_DICTIONARY_TYPE` metadata; untyped `Variant` sides contribute
/// no spec, and two of them yield no hint.
pub fn resolveDictionary(comptime Key: type, comptime Value: type) ?Resolved {
    comptime {
        const key_spec = sideSpec(Key);
        const value_spec = sideSpec(Value);
        if (value_spec) |spec| {
            const value_text = spec.format();
            if (key_spec) |key| {
                return .{
                    .hint = .dictionary_type,
                    .hint_string = std.fmt.comptimePrint("{s};{s}", .{ key.format(), value_text }),
                    .class_name = null,
                };
            }
            return .{
                .hint = .dictionary_type,
                .hint_string = std.fmt.comptimePrint(";{s}", .{value_text}),
                .class_name = null,
            };
        }
        if (key_spec) |key| {
            return .{
                .hint = .dictionary_type,
                .hint_string = key.format(),
                .class_name = null,
            };
        }
        return null;
    }
}

/// Detects the container shape declared on `T`: its engine container type plus
/// the `Element` or `Key`/`Value` type declarations; null when neither applies.
pub fn declaredContainer(comptime T: type) ?DeclaredContainer {
    comptime {
        const Engine = conversion.engineType(T) orelse return null;
        if (Engine == builtins.Array) {
            const Element = declaredType(T, "Element") orelse return null;
            return .{ .array = .{ .element = Element } };
        }
        if (Engine == builtins.Dictionary) {
            const Key = declaredType(T, "Key");
            const Value = declaredType(T, "Value");
            if (Key == null and Value == null) return null;
            return .{ .dictionary = .{ .key = Key, .value = Value } };
        }
        return null;
    }
}

/// The type declared under `name` on `T`, or null.
fn declaredType(comptime T: type, comptime name: []const u8) ?type {
    comptime {
        switch (@typeInfo(T)) {
            .@"struct", .@"enum", .@"union", .@"opaque" => {},
            else => return null,
        }
        if (!@hasDecl(T, name)) return null;
        const Decl = @field(T, name);
        if (@TypeOf(Decl) != type) return null;
        return Decl;
    }
}

/// One typed-container side: `<variant type>/<hint>:<hint string>`.
const SideSpec = struct {
    variant_type: interface.VariantType,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,

    /// Encodes the engine hint format, for example `"24/34:Node"`.
    fn format(comptime spec: SideSpec) [:0]const u8 {
        return std.fmt.comptimePrint("{d}/{d}:{s}", .{
            @backingInt(spec.variant_type),
            @backingInt(spec.hint),
            spec.hint_string,
        });
    }
};

/// Resolves one element/key/value type to its container hint spec: the
/// node/resource picker for object types, the converter's engine hint when it
/// has one, otherwise the declared type's hint. `Variant` is untyped, no spec.
fn sideSpec(comptime T: type) ?SideSpec {
    comptime {
        if (T == builtins.Variant) return null;
        const variant_type = conversion.variantType(T) orelse return null;
        if (conversion.engineType(T)) |Engine| {
            if (reflect.objectTarget(Engine)) |target| {
                return .{
                    .variant_type = variant_type,
                    .hint = if (reflect.isNodeClass(target.class)) .node_type else .resource_type,
                    .hint_string = conversion.engineClassName(T),
                };
            }
        }
        if (resolveConverted(T)) |converted| {
            return .{
                .variant_type = variant_type,
                .hint = converted.hint,
                .hint_string = converted.hint_string,
            };
        }
        if (resolve(T)) |resolved| {
            return .{
                .variant_type = variant_type,
                .hint = resolved.hint,
                .hint_string = resolved.hint_string,
            };
        }
        return .{
            .variant_type = variant_type,
            .hint = .none,
            .hint_string = "",
        };
    }
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const builtins = @import("../builtins/builtins.zig");
const conversion = @import("../conversion.zig");
const enums = @import("../enums.zig");
const reflect = @import("../reflect/reflect.zig");
const constants = @import("constants.zig");
