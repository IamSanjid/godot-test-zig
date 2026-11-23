//! Compile-only coverage for `godot.reflect.extendsType` / `inheritsFrom`.
//!
//! Fake declarations keep the pure `Extends` primitive honest; generated engine
//! classes are exercised by the `objects.zig` and `extension.zig` tests.

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
    check(reflect.extendsType(FakeChild) == FakeParent, "extendsType must report the direct parent");
    check(reflect.extendsType(FakeParent) == FakeRoot, "extendsType must report the direct parent");
    check(reflect.extendsType(NoExtends) == null, "a declaration without Extends has no parent");
    check(reflect.extendsType(NonTypeExtends) == null, "a non-type Extends value has no parent");
    check(reflect.extendsType(u32) == null, "primitives have no class hierarchy");
    check(reflect.extendsType(*u32) == null, "pointers have no class hierarchy");

    check(reflect.inheritsFrom(FakeChild, FakeRoot), "transitive inheritance must be found");
    check(reflect.inheritsFrom(FakeChild, FakeParent), "direct inheritance must be found");
    check(reflect.inheritsFrom(FakeChild, FakeChild), "a class inherits from itself");
    check(reflect.inheritsFrom(FakeRoot, FakeRoot), "a root class inherits from itself");
    check(!reflect.inheritsFrom(FakeParent, FakeChild), "inheritance is directional");
    check(!reflect.inheritsFrom(NoExtends, FakeRoot), "a declaration without Extends inherits from nothing else");
    check(!reflect.inheritsFrom(NonTypeExtends, FakeRoot), "a non-type Extends value ends the walk");
    check(!reflect.inheritsFrom(u32, FakeRoot), "primitives inherit from nothing else");
}

comptime {
    comptimeChecks();
}

test "extends traversal" {
    comptime comptimeChecks();
}

const godot = @import("godot");
const reflect = godot.reflect;
