//! Declared property type -> engine hint metadata. See docs/properties.md.

/// Engine hint metadata resolved from a property's declared Zig type.
pub const Resolved = struct {
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    /// Engine class name for object pointers; null for enums/bitfields and
    /// builtins that have no hint.
    class_name: ?[:0]const u8,
};

/// Resolves a declared property value type to an engine hint.
///
/// Enums and bitpack structs resolve from their Zig declaration alone. Object
/// pointers resolve to a node/resource picker hint when the class inherits
/// `Node` or `Resource`; other object pointers get no picker hint but still
/// expose the class name. Plain builtins have no type-inherent hint and return
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

const enums = @import("../enums.zig");
const reflect = @import("../reflect/reflect.zig");
const constants = @import("constants.zig");
