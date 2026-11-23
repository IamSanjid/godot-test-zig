/// Base marker: stores the direct parent instance and is initialized during creation.
pub fn Base(comptime T: type) type {
    return struct {
        pub const BaseFor = T;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.base;

        base_ptr: *T = undefined,
        safe_guard: SafeGuard = .{},

        const Self = @This();

        pub fn get(self: *const Self) *T {
            return self.safe_guard.getGuard(*T, getImpl, .{self});
        }

        fn getImpl(self: *const Self) *T {
            return self.base_ptr;
        }

        pub fn set(self: *Self, value: *T) void {
            self.safe_guard.setGuard(setImpl, .{ self, value });
        }

        fn setImpl(self: *Self, value: *T) void {
            self.base_ptr = value;
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

const reflect_base = @import("../reflect/base.zig");
const SafeGuard = @import("internal/SafeGuard.zig");
const marker_kind = @import("marker.zig");
