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

pub fn isEngineClass(comptime T: type) bool {
    if (auto.isNamespace(T)) return false;
    if (!@hasDecl(T, "Extends")) return false;

    const Extends = T.Extends;
    const can_be_engine_class = auto.isNormalStruct(Extends) or auto.isOpaque(Extends);
    return can_be_engine_class and auto.inheritsFrom(Extends, classes.core.Object);
}

const std = @import("std");

const auto = @import("auto.zig");
const classes = @import("../classes/classes.zig");
