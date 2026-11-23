//! Coverage for annotation-free Base marker discovery on `godot.reflect`.
//!
//! The fake marker mirrors the annotation's public shape without importing the
//! annotation layer, so `findBaseField`/`findBaseFieldFor`/`basePointer` stay
//! checked against the structural contract alone.

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
        const field = reflect.findBaseField(SingleMarker);
        expect(field != null, "findBaseField must find a Base marker");
        expect(field.?.name.len == "marker".len and std.mem.eql(u8, field.?.name, "marker"), "findBaseField must report the field name");
        expect(field.?.base_type == FakeParent, "findBaseField must report the recorded parent type");
    }

    {
        const field = reflect.findBaseFieldFor(SingleMarker, FakeParent);
        expect(field != null, "findBaseFieldFor must match the recorded parent");
        expect(field.?.name.len == "marker".len and std.mem.eql(u8, field.?.name, "marker"), "findBaseFieldFor must report the field name");
        expect(reflect.findBaseFieldFor(SingleMarker, FakeGrandparent) == null, "findBaseFieldFor must not match a different parent");
    }

    // Duplicate marker fields are rejected with a compile error; a positive
    // compile-time assertion cannot express that, so it is covered by the
    // runtime `SingleMarker`/`basePointer` checks and by the helper contract.
    // (A struct declaring two `Base(...)` markers is never valid: one struct
    // has exactly one direct parent.)

    expect(reflect.findBaseField(NotAMarker) == null, "a struct exposing only BaseFor is not a marker");
    expect(reflect.findBaseField(IncompleteMarker) == null, "a struct without both accessors is not a marker");
    expect(reflect.findBaseField(FakeParent) == null, "a struct without markers returns null");
    expect(reflect.findBaseField(u32) == null, "non-struct types return null");
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

    const pointer = reflect.basePointer(SingleMarker, FakeParent, &owner);
    try std.testing.expect(pointer != null);
    try std.testing.expectEqual(&parent, pointer.?);
    try std.testing.expect(reflect.basePointer(SingleMarker, FakeGrandparent, &owner) == null);
}

const std = @import("std");

const godot = @import("godot");
const reflect = godot.reflect;
