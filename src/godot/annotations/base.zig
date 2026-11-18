/// Basically a marker, which marks a field as a pointer to the Base, and usually will be set during initialization.
pub fn Base(comptime T: type) type {
    return struct {
        pub const BaseFor = T;

        _ptr: *T = undefined,
        _safe_guard: SafeGuard = .{},

        const Self = @This();

        pub fn get(self: *const Self) *T {
            return self._safe_guard.getGuard(*T, getImpl, .{self});
        }

        fn getImpl(self: *const Self) *T {
            return self._ptr;
        }

        pub fn set(self: *Self, value: *T) void {
            self._safe_guard.setGuard(setImpl, .{ self, value });
        }

        fn setImpl(self: *Self, value: *T) void {
            self._ptr = value;
        }
    };
}

pub fn initBase(comptime T: type, comptime B: type, to: *T, base: *B) void {
    const type_info = @typeInfo(T);
    if (comptime type_info != .@"struct") return;
    const field_name_opt = comptime findBaseFieldName(T, B);
    if (field_name_opt) |field_name| {
        @field(to, field_name) = .{};
        @field(to, field_name).set(base);
    }
}

/// Returns the single Base marker field name on `T`, or null if there is none.
///
/// Marker discovery itself is generic and annotation-free: it lives in
/// `reflect.base` so `Variant` and registration can find Base markers without
/// importing annotations. This wrapper keeps the annotation layer's public API
/// and its struct-only diagnostic.
pub fn findBaseFieldName(comptime T: type, comptime B: type) ?[:0]const u8 {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type, found " ++ @typeName(T));
    const field = comptime reflect_base.findBaseFieldFor(T, B) orelse return null;
    return field.name;
}

// ---------------------------------------------------------------------------
// Compile-time coverage: markers built by this annotation must stay discoverable
// by the annotation-free reflect layer, because `Variant` and registration use
// that layer. This runs on every build that references annotations.
// ---------------------------------------------------------------------------

const TestParent = struct { value: u32 = 0 };

const TestExtension = struct {
    base: Base(TestParent) = .{},
};

fn checkAnnotationMarker() void {
    const field = reflect_base.findBaseFieldFor(TestExtension, TestParent) orelse
        @compileError("annotations.Base marker is not discoverable by reflect.base");
    if (field.base_type != TestParent) @compileError("reflect.base reports the wrong Base marker parent type");
    if (!std.mem.eql(u8, field.name, "base")) @compileError("reflect.base reports the wrong Base marker field name");
    if (findBaseFieldName(TestExtension, TestParent) == null)
        @compileError("findBaseFieldName must keep finding annotation markers");
}

comptime {
    checkAnnotationMarker();
}

test "reflect.base discovers annotations.Base markers" {
    comptime checkAnnotationMarker();

    var parent: TestParent = .{};
    var extension: TestExtension = .{};
    extension.base.set(&parent);

    const pointer = reflect_base.basePointer(TestExtension, TestParent, &extension);
    try std.testing.expect(pointer != null);
    try std.testing.expectEqual(&parent, pointer.?);
}

const SafeGuard = @import("internal/safe_guard.zig");

const std = @import("std");

const reflect_base = @import("../reflect/base.zig");
