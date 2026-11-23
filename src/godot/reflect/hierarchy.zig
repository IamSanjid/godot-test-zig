//! Generic `Extends` hierarchy traversal.

/// The direct parent declared by `T.Extends`, or null when `T` declares no
/// `Extends` or its `Extends` value is not a type.
///
/// Only struct and opaque declarations are class declarations; primitive types,
/// pointers, enums, and unions have no class hierarchy and return null.
pub fn extendsType(comptime T: type) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct" and info != .@"opaque") return null;
    if (!@hasDecl(T, "Extends")) return null;
    const Parent = T.Extends;
    if (@TypeOf(Parent) != type) return null;
    return Parent;
}

/// Follow `Extends` until `Base` is found.
///
/// Engine classes and extension classes both participate. `T == Base` is a
/// match, so a class inherits from itself. A declaration without a usable
/// `Extends` ends the walk in `false`; malformed cyclic declarations are
/// stopped by the compile-time branch quota.
pub fn inheritsFrom(comptime T: type, comptime Base: type) bool {
    @setEvalBranchQuota(1500); // around 1000 classes are in the Godot engine.
    comptime var Cur = T;
    inline while (true) {
        if (Cur == Base) return true;
        Cur = extendsType(Cur) orelse return false;
    }
}
