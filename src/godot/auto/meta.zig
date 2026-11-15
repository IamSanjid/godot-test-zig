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

pub fn isNamespace(comptime T: type) bool {
    if (isNormalStruct(T) or isTuple(T)) return false;
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    const struct_info = info.@"struct";
    return struct_info.field_names.len == 0;
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
    const info = @typeInfo(@TypeOf(f));
    return info == .@"fn";
}

pub fn FnReturnType(comptime f: anytype) ?type {
    const info = @typeInfo(@TypeOf(f));
    if (info != .@"fn") @compileError("Expected a fn but found: " ++ @typeName(@TypeOf(f)));
    return info.@"fn".return_type;
}
