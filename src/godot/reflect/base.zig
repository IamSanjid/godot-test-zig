//! Annotation-free discovery of Base marker fields.

/// A discovered base-marker field.
pub const BaseField = struct {
    /// Name of the field on the owning struct.
    name: [:0]const u8,
    /// Parent class type recorded by the marker (`Marker.BaseFor`).
    base_type: type,
};

/// The single base-marker field of `T`, or null when `T` has none.
///
/// Returns null for non-struct types and tuples. Compile-errors when `T`
/// declares more than one base marker field.
pub fn findBaseField(comptime T: type) ?BaseField {
    const info = @typeInfo(T);
    if (info != .@"struct") return null;
    const struct_info = info.@"struct";
    if (struct_info.is_tuple) return null;

    comptime var found: ?BaseField = null;
    inline for (struct_info.field_names, struct_info.field_types) |field_name, FieldType| {
        if (comptime isBaseMarker(FieldType)) {
            if (found) |existing| {
                @compileError("Type '" ++ @typeName(T) ++ "' declares more than one base marker field ('" ++
                    existing.name ++ "' and '" ++ field_name ++
                    "'); an extension class must have exactly one direct parent.");
            }
            found = .{ .name = field_name, .base_type = FieldType.BaseFor };
        }
    }
    return found;
}

/// The base-marker field of `T` for parent class `B`, or null when `T` has no
/// `Base(B)` marker.
///
/// Returns null for non-struct types and tuples. Compile-errors when `T`
/// declares more than one `Base(B)` marker.
pub fn findBaseFieldFor(comptime T: type, comptime B: type) ?BaseField {
    const info = @typeInfo(T);
    if (info != .@"struct") return null;
    const struct_info = info.@"struct";
    if (struct_info.is_tuple) return null;

    comptime var found: ?BaseField = null;
    inline for (struct_info.field_names, struct_info.field_types) |field_name, FieldType| {
        if (comptime isBaseMarker(FieldType)) {
            if (comptime FieldType.BaseFor == B) {
                if (found) |existing| {
                    @compileError("Type '" ++ @typeName(T) ++ "' declares more than one Base(" ++
                        @typeName(B) ++ ") marker field ('" ++ existing.name ++ "' and '" ++ field_name ++ "').");
                }
                found = .{ .name = field_name, .base_type = B };
            }
        }
    }
    return found;
}

/// The direct parent instance recorded by `T`'s `Base(B)` marker field, or null
/// when `T` has no such field.
///
/// The returned pointer is borrowed from `instance`; nothing is copied and no
/// ownership changes.
pub fn basePointer(comptime T: type, comptime B: type, instance: *const T) ?*B {
    const field = (comptime findBaseFieldFor(T, B)) orelse return null;
    return @field(instance.*, field.name).get();
}

/// True when `FieldType` is a struct with the structural shape of a base marker:
/// a normal struct declaring `BaseFor` (a type), `get` and `set` functions.
fn isBaseMarker(comptime FieldType: type) bool {
    if (!meta.isNormalStruct(FieldType)) return false;
    if (!@hasDecl(FieldType, "BaseFor")) return false;
    if (@TypeOf(FieldType.BaseFor) != type) return false;
    return isFunctionDecl(FieldType, "get") and isFunctionDecl(FieldType, "set");
}

/// True when `T` declares `name` as a function.
fn isFunctionDecl(comptime T: type, comptime name: [:0]const u8) bool {
    if (!@hasDecl(T, name)) return false;
    return @typeInfo(@TypeOf(@field(T, name))) == .@"fn";
}

const meta = @import("meta.zig");
