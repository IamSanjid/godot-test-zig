//! Generic `Extends` hierarchy traversal: the pure class-hierarchy primitive.
//!
//! A class declaration records its direct parent as `pub const Extends = Parent`
//! (generated engine classes and Zig extension classes both do this; generated
//! root classes declare `Extends = void`). This module only walks that
//! declaration. It knows nothing about generated engine classes, extension
//! classes, Base markers, or registration; `objects.zig` and `extension.zig`
//! add that policy on top.
//!
//! Everything here is comptime-only.

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

// ---------------------------------------------------------------------------
// Compile-only coverage with fake declarations. Higher layers (`objects.zig`,
// `extension.zig`) check generated classes; this check keeps the primitive
// itself honest on every build that references `reflect`.
// ---------------------------------------------------------------------------

const FakeRoot = struct {};

const FakeParent = struct {
    pub const Extends = FakeRoot;
};

const FakeChild = struct {
    pub const Extends = FakeParent;
    value: u32 = 0,
};

/// Root declarations may not have an `Extends` declaration at all.
const NoExtends = struct {
    value: u32 = 0,
};

/// `Extends` must be a type; other declarations are ignored.
const NonTypeExtends = struct {
    pub const Extends = 42;
};

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("reflect.hierarchy: " ++ message);
}

fn comptimeChecks() void {
    check(extendsType(FakeChild) == FakeParent, "extendsType must report the direct parent");
    check(extendsType(FakeParent) == FakeRoot, "extendsType must report the direct parent");
    check(extendsType(NoExtends) == null, "a declaration without Extends has no parent");
    check(extendsType(NonTypeExtends) == null, "a non-type Extends value has no parent");
    check(extendsType(u32) == null, "primitives have no class hierarchy");
    check(extendsType(*u32) == null, "pointers have no class hierarchy");

    check(inheritsFrom(FakeChild, FakeRoot), "transitive inheritance must be found");
    check(inheritsFrom(FakeChild, FakeParent), "direct inheritance must be found");
    check(inheritsFrom(FakeChild, FakeChild), "a class inherits from itself");
    check(inheritsFrom(FakeRoot, FakeRoot), "a root class inherits from itself");
    check(!inheritsFrom(FakeParent, FakeChild), "inheritance is directional");
    check(!inheritsFrom(NoExtends, FakeRoot), "a declaration without Extends inherits from nothing else");
    check(!inheritsFrom(NonTypeExtends, FakeRoot), "a non-type Extends value ends the walk");
    check(!inheritsFrom(u32, FakeRoot), "primitives inherit from nothing else");
}

comptime {
    comptimeChecks();
}

/// Runs this module's compile-only checks. `reflect.zig` calls it from a
/// container-level `comptime` block so a plain build analyzes this module (and
/// its checks) even while no runtime caller references the helpers yet.
pub fn comptimeSelfCheck() void {
    comptimeChecks();
}

test "extends traversal" {
    comptime comptimeChecks();
}
