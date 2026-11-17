pub fn inheritsFrom(comptime T: type, comptime Base: type) bool {
    @setEvalBranchQuota(1500); // around 1000 classes are in the Godot engine.
    comptime var Cur = T;
    inline while (true) {
        if (Cur == Base) return true;
        if (@TypeOf(Cur) != type) return false;
        const info = @typeInfo(Cur);
        if (info != .@"struct" and info != .@"opaque") return false;
        if (!@hasDecl(Cur, "Extends")) return false;
        Cur = Cur.Extends;
    }
}

/// True when T is `RefCounted` or descends from it.
pub fn isRefCounted(comptime T: type) bool {
    return inheritsFrom(T, classes.core.RefCounted);
}

/// True for a pointer/optional-pointer whose pointee is `RefCounted` or a
/// descendant of it.
pub fn isRefCountedPointer(comptime T: type) bool {
    return isRefCounted(meta.ValueType(T));
}

pub fn isEngineClass(comptime T: type) bool {
    if (!@hasDecl(T, "Extends")) return false;

    const Extends = T.Extends;
    const can_be_engine_class = reflect.isNormalStruct(Extends) or reflect.isOpaque(Extends);
    return can_be_engine_class and reflect.inheritsFrom(Extends, classes.core.Object);
}

const std = @import("std");

const reflect = @import("reflect.zig");
const meta = @import("meta.zig");
const classes = @import("../classes/classes.zig");
