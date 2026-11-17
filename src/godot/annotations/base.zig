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
/// Rejects duplicate.
pub fn findBaseFieldName(comptime T: type, comptime B: type) ?[:0]const u8 {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type, found " ++ @typeName(T));

    comptime var found: ?[:0]const u8 = null;
    inline for (info.@"struct".field_types, info.@"struct".field_names) |FType, f_name| {
        if (isBaseMarker(FType, B)) {
            if (found != null)
                @compileError("Found more than one Base(" ++ @typeName(B) ++ ") marked field, there should be only one.");
            found = f_name;
        }
    }
    return found;
}

/// True if `FTypec` is a type produced by `Base(...)`.
fn isBaseMarker(comptime FType: type, comptime B: type) bool {
    return comptime reflect.isNormalStruct(FType) and
        @hasDecl(FType, "BaseFor") and
        Base(FType.BaseFor) == FType and
        Base(B) == FType;
}

const SafeGuard = @import("internal/safe_guard.zig");

const reflect = @import("../reflect/reflect.zig");
