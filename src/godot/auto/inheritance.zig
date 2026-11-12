pub fn inheritsFrom(comptime T: type, comptime Base: type) bool {
    @setEvalBranchQuota(1500); // around 1000 classes are in the Godot engine.
    comptime var Cur = T;
    inline while (true) {
        if (Cur == Base) return true;
        if (!@hasDecl(Cur, "Extends")) return false;
        Cur = Cur.Extends;
    }
}

const std = @import("std");
