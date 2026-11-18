pub fn isTuple(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .@"struct" and info.@"struct".is_tuple;
}

pub fn isOpaque(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .@"opaque";
}

/// if a struct has a field and the size of it is > 0
pub fn isNormalStruct(comptime T: type) bool {
    if (isTuple(T) or isOpaque(T)) return false;
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    return info.@"struct".field_names.len > 0 and @sizeOf(T) > 0;
}

/// Best-effort namespace detector: a zero-field non-tuple struct.
/// `Extends`/engine-class checks stay with callers that need them.
pub fn isLikelyNamespace(comptime T: type) bool {
    if (isNormalStruct(T) or isTuple(T)) return false;
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    const struct_info = info.@"struct";
    return struct_info.field_names.len == 0;
}

/// Canonical extension-class name: `GodotClassName` when present, otherwise
/// the exact short Zig type name.
pub fn className(comptime T: type) [:0]const u8 {
    if (@hasDecl(T, "GodotClassName")) return T.GodotClassName;
    const full = @typeName(T);
    const pos = std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
    return full[pos + 1 ..];
}

pub fn isSelfType(comptime Self: type, comptime T: type) bool {
    return T == Self or T == *Self or T == *const Self;
}

pub fn isSelfPtrType(comptime Self: type, comptime T: type) bool {
    return T == *Self or T == *const Self;
}

pub fn hasAllDefaults(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    inline for (@typeInfo(T).@"struct".field_attrs) |attr| {
        if (attr.default_value_ptr == null) return false;
    }
    return true;
}

pub fn isNormalFunction(comptime function: anytype) bool {
    const MethodT = @TypeOf(function);
    const type_info = @typeInfo(MethodT);
    if (type_info != .@"fn") return false;
    const fn_info = type_info.@"fn";
    if (fn_info.is_generic) return false;
    if (fn_info.return_type == null) return false;
    return true;
}

/// True for `?*T` and `?*const T` pointer optionals.
///
/// Only single-item pointer optionals qualify: optional many-pointers
/// (`?[*]T`, `?[*:0]T`) and optional slices (`?[]T`) are not pointer optionals.
pub fn isOptionalPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => |pointer| pointer.size == .one,
            else => false,
        },
        else => false,
    };
}

pub fn ValueType(comptime T: type) type {
    const info = @typeInfo(T);
    return switch (info) {
        .pointer => |p| ValueType(p.child),
        .optional => |o| ValueType(o.child),
        .array => |a| ValueType(a.child),
        .vector => |v| ValueType(v.child),
        else => T,
    };
}

pub fn isFn(comptime f: anytype) bool {
    const F = @TypeOf(f);
    const info = if (F == type) @typeInfo(f) else @typeInfo(F);
    return info == .@"fn";
}

pub fn FnReturnType(comptime f: anytype) ?type {
    const F = @TypeOf(f);
    const info = if (F == type) @typeInfo(f) else @typeInfo(F);
    if (info != .@"fn") @compileError("Expected a fn but found: " ++ @typeName(@TypeOf(f)));
    return info.@"fn".return_type;
}

test "isOptionalPointer accepts single-item pointer optionals only" {
    try std.testing.expect(isOptionalPointer(?*u32));
    try std.testing.expect(isOptionalPointer(?*const u32));
    try std.testing.expect(isOptionalPointer(?*anyopaque));
    try std.testing.expect(!isOptionalPointer(*u32));
    try std.testing.expect(!isOptionalPointer(*const u32));
    try std.testing.expect(!isOptionalPointer(u32));
    try std.testing.expect(!isOptionalPointer(?u32));
    try std.testing.expect(!isOptionalPointer(?[*]u32));
    try std.testing.expect(!isOptionalPointer(?[*:0]u32));
    try std.testing.expect(!isOptionalPointer(?[]u32));
}

const std = @import("std");
