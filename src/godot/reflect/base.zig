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

// Compile-only coverage with fake markers.
//
// The fake marker mirrors the annotation's public shape without importing the
// annotation layer. `comptime` evaluation below runs on every build that
// references `reflect`, so the helper contracts stay checked.

fn FakeMarker(comptime B: type) type {
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

const FakeParent = struct { value: u32 = 1 };
const FakeGrandparent = struct { value: u32 = 2 };

const SingleMarker = struct {
    marker: FakeMarker(FakeParent) = .{},
};

/// A struct that only exposes `BaseFor` is not a marker.
const NotAMarker = struct {
    marker: struct {
        pub const BaseFor = FakeParent;
        value: u32 = 0,
    } = .{},
};

/// A struct that names `BaseFor` but lacks the accessor declarations.
const IncompleteMarker = struct {
    marker: struct {
        pub const BaseFor = FakeParent;
        value: u32 = 0,

        pub fn get(_: *const @This()) *FakeParent {
            unreachable;
        }
    } = .{},
};

fn expect(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("reflect.base: " ++ message);
}

fn comptimeChecks() void {
    {
        const field = findBaseField(SingleMarker);
        expect(field != null, "findBaseField must find a Base marker");
        expect(field.?.name.len == "marker".len and std.mem.eql(u8, field.?.name, "marker"), "findBaseField must report the field name");
        expect(field.?.base_type == FakeParent, "findBaseField must report the recorded parent type");
    }

    {
        const field = findBaseFieldFor(SingleMarker, FakeParent);
        expect(field != null, "findBaseFieldFor must match the recorded parent");
        expect(field.?.name.len == "marker".len and std.mem.eql(u8, field.?.name, "marker"), "findBaseFieldFor must report the field name");
        expect(findBaseFieldFor(SingleMarker, FakeGrandparent) == null, "findBaseFieldFor must not match a different parent");
    }

    // Duplicate marker fields are rejected with a compile error; a positive
    // compile-time assertion cannot express that, so it is covered by the
    // runtime `SingleMarker`/`basePointer` checks and by the helper contract.
    // (A struct declaring two `Base(...)` markers is never valid: one struct
    // has exactly one direct parent.)

    expect(findBaseField(NotAMarker) == null, "a struct exposing only BaseFor is not a marker");
    expect(findBaseField(IncompleteMarker) == null, "a struct without both accessors is not a marker");
    expect(findBaseField(FakeParent) == null, "a struct without markers returns null");
    expect(findBaseField(u32) == null, "non-struct types return null");
}

comptime {
    comptimeChecks();
}

test "base marker discovery" {
    comptime comptimeChecks();
}

test "basePointer returns the recorded parent instance" {
    var parent: FakeParent = .{};
    var owner: SingleMarker = .{};
    owner.marker.set(&parent);

    const pointer = basePointer(SingleMarker, FakeParent, &owner);
    try std.testing.expect(pointer != null);
    try std.testing.expectEqual(&parent, pointer.?);
    try std.testing.expect(basePointer(SingleMarker, FakeGrandparent, &owner) == null);
}

const std = @import("std");
const meta = @import("meta.zig");
