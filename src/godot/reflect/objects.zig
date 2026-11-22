//! Engine/extension object class reflection and object-pointer classification.

/// Upper bound for `Extends`-chain walks. Valid class hierarchies are far
/// shorter; the bound turns a malformed cyclic chain into `false` instead of a
/// compiler hang.
const max_extends_depth: usize = 512;

/// True when `T` is `RefCounted` or descends from it.
pub fn isRefCounted(comptime T: type) bool {
    return hierarchy.inheritsFrom(T, classes.core.RefCounted);
}

/// True for a single-item pointer/optional pointer whose target is a class type
/// that is `RefCounted` or descends from it.
///
/// Accepts `*C`, `*const C`, `?*C` and `?*const C`. Class values (`C`), arrays,
/// many-pointers (`[*]C`), slices (`[]C`) and optionals of those are not object
/// pointers, even when their element is RefCounted.
pub fn isRefCountedPointer(comptime T: type) bool {
    const target = objectTarget(T) orelse return false;
    return isRefCounted(target.class);
}

/// How a class relates to the engine.
pub const ObjectKind = enum {
    /// Opaque generated engine class (`classes.core.Object`, ...).
    engine,
    /// Zig struct extension class with a valid `Extends` chain.
    extension,
};

/// A class type behind a pointer/optional-pointer value type.
pub const ObjectTarget = struct {
    /// Pointee class type: `C` for `*C`, `*const C`, `?*C` and `?*const C`.
    class: type,
    kind: ObjectKind,
    /// True for optional pointers (`?*C`).
    optional: bool = false,
    /// True for const pointers (`*const C`).
    is_const: bool = false,
};

/// True for an opaque generated engine class: a class declaration defined by
/// the engine (`classes.core.Object` or one of its descendants).
pub fn isEngineObjectClass(comptime T: type) bool {
    if (@typeInfo(T) != .@"opaque") return false;
    return hierarchy.inheritsFrom(T, classes.core.Object);
}

/// True for a Zig struct whose `Extends` chain reaches an engine object class.
/// The chain may pass through other extension classes. Zero-field extension
/// declarations are valid; use `isLikelyNamespace` to distinguish namespaces.
pub fn isExtensionClass(comptime T: type) bool {
    @setEvalBranchQuota(2000);
    if (@typeInfo(T) != .@"struct") return false;
    const Extends = hierarchy.extendsType(T) orelse return false;
    return extensionChainReachesEngine(Extends, 1);
}

/// True for either an engine object class or an extension class.
pub fn isClassType(comptime T: type) bool {
    return isEngineObjectClass(T) or isExtensionClass(T);
}

/// The class behind a pointer/optional-pointer type, or null when `T` is not a
/// single-item pointer to a class type.
///
/// Accepts `*C`, `*const C`, `?*C` and `?*const C`; class values (`C`), many
/// pointers (`[*]C`) and slices (`[]C`) are not object pointers.
pub fn objectTarget(comptime T: type) ?ObjectTarget {
    const info = @typeInfo(T);
    return switch (info) {
        .pointer => |pointer| if (pointer.size == .one)
            targetOf(pointer.child, false, pointer.attrs.@"const")
        else
            null,
        .optional => |optional| switch (@typeInfo(optional.child)) {
            .pointer => |pointer| if (pointer.size == .one)
                targetOf(pointer.child, true, pointer.attrs.@"const")
            else
                null,
            else => null,
        },
        else => null,
    };
}

/// The class type behind a pointer/optional-pointer type, or null.
pub fn objectClassOf(comptime T: type) ?type {
    const target = objectTarget(T) orelse return null;
    return target.class;
}

/// The engine class name of an object pointer type; empty for non-objects.
pub fn classNameOf(comptime T: type) [:0]const u8 {
    const Class = objectClassOf(T) orelse return "";
    return meta.className(Class);
}

/// True for `*C`, `*const C`, `?*C` or `?*const C` where `C` is a class type.
pub fn isObjectPointer(comptime T: type) bool {
    return objectTarget(T) != null;
}

fn extensionChainReachesEngine(comptime T: type, comptime depth: usize) bool {
    if (depth > max_extends_depth) return false;
    if (isEngineObjectClass(T)) return true;
    if (@typeInfo(T) != .@"struct") return false;
    const Extends = hierarchy.extendsType(T) orelse return false;
    return extensionChainReachesEngine(Extends, depth + 1);
}

fn targetOf(comptime Class: type, comptime optional: bool, comptime is_const: bool) ?ObjectTarget {
    const kind: ObjectKind = if (comptime isEngineObjectClass(Class))
        .engine
    else if (comptime isExtensionClass(Class))
        .extension
    else
        return null;

    return .{
        .class = Class,
        .kind = kind,
        .optional = optional,
        .is_const = is_const,
    };
}

// Compile-only coverage with fake extension classes over real engine classes.
//
// The fakes classify types only: extension -> engine base resolution (and the
// Base markers it requires) is covered by `extension.zig`. `comptime` evaluation
// below runs on every build that references `reflect`.

const EngineObject = classes.core.Object;
const EngineNode = classes.core.Node;

/// Direct extension class over an engine class; no Base marker needed to be
/// classified as an extension class.
const DirectExtension = struct {
    pub const Extends = EngineNode;
};

/// Extension class whose `Extends` is another extension class.
const ChainedExtension = struct {
    pub const Extends = DirectExtension;
    value: u32 = 0,
};

/// Zero-field extension declarations are valid extension classes.
const ZeroFieldExtension = struct {
    pub const Extends = EngineNode;
};

/// Extension class over a RefCounted descendant.
const RefCountedExtension = struct {
    pub const Extends = classes.core.RefCounted;
};

const NotAClass = struct {
    value: u32 = 0,
};

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("reflect.objects: " ++ message);
}

fn comptimeChecks() void {
    check(isEngineObjectClass(EngineObject), "classes.core.Object must be an engine object class");
    check(isEngineObjectClass(EngineNode), "classes.core.Node must be an engine object class");
    check(!isEngineObjectClass(DirectExtension), "an extension class is not an engine object class");
    check(!isEngineObjectClass(NotAClass), "a plain struct is not an engine object class");
    check(!isEngineObjectClass(u32), "a scalar is not an engine object class");

    check(isExtensionClass(DirectExtension), "a struct extending an engine class is an extension class");
    check(isExtensionClass(ChainedExtension), "extension -> extension chains are extension classes");
    check(isExtensionClass(ZeroFieldExtension), "zero-field extension classes are extension classes");
    check(isExtensionClass(RefCountedExtension), "extension classes may extend any engine object class");
    check(!isExtensionClass(EngineNode), "engine object classes are not extension classes");
    check(!isExtensionClass(NotAClass), "a struct without Extends is not an extension class");
    check(!isExtensionClass(u32), "a scalar is not an extension class");

    check(isClassType(EngineObject) and isClassType(EngineNode), "engine object classes are class types");
    check(isClassType(DirectExtension) and isClassType(ChainedExtension) and isClassType(ZeroFieldExtension), "extension classes are class types");
    check(!isClassType(u32) and !isClassType(NotAClass), "non-class types are not class types");

    check(isRefCounted(classes.core.RefCounted), "RefCounted is refcounted");
    check(!isRefCounted(EngineObject), "Object is not refcounted");
    check(!isRefCounted(EngineNode), "Node is not refcounted");
    check(isRefCounted(RefCountedExtension), "an extension class over RefCounted is refcounted");
    check(!isRefCounted(DirectExtension), "an extension class over Node is not refcounted");
    check(!isRefCounted(u32), "a scalar is not refcounted");

    check(isRefCountedPointer(*classes.core.RefCounted), "*RefCounted is a refcounted pointer");
    check(isRefCountedPointer(?*const classes.core.RefCounted), "?*const RefCounted is a refcounted pointer");
    check(isRefCountedPointer(*const RefCountedExtension), "*RefCountedExtension is a refcounted pointer");
    check(!isRefCountedPointer(classes.core.RefCounted), "a class value is not a refcounted pointer");
    check(!isRefCountedPointer(*EngineNode), "an Object/Node pointer is not refcounted");
    check(!isRefCountedPointer(*DirectExtension), "an extension over Node is not refcounted");
    check(!isRefCountedPointer([2]*classes.core.RefCounted), "an array of RefCounted pointers is not a refcounted pointer");
    check(!isRefCountedPointer([*]*classes.core.RefCounted), "a many-pointer to RefCounted pointers is not a refcounted pointer");
    check(!isRefCountedPointer([]*classes.core.RefCounted), "a slice of RefCounted pointers is not a refcounted pointer");
    check(!isRefCountedPointer(?[*]*classes.core.RefCounted), "an optional many-pointer is not a refcounted pointer");
    check(!isRefCountedPointer(*u32), "a scalar pointer is not a refcounted pointer");
    check(!isRefCountedPointer(u32), "a scalar is not a refcounted pointer");

    {
        const target = objectTarget(*EngineNode);
        check(target != null, "*EngineNode must be an object pointer");
        check(target.?.class == EngineNode, "objectTarget must report the pointee class");
        check(target.?.kind == .engine, "*EngineNode must be reported as engine kind");
        check(!target.?.optional and !target.?.is_const, "*EngineNode is a mutable non-optional pointer");
    }
    {
        const target = objectTarget(?*const EngineNode);
        check(target != null, "?*const EngineNode must be an object pointer");
        check(target.?.kind == .engine, "?*const EngineNode must be reported as engine kind");
        check(target.?.optional and target.?.is_const, "?*const EngineNode is an optional const pointer");
    }
    {
        const target = objectTarget(*DirectExtension);
        check(target != null, "*Extension must be an object pointer");
        check(target.?.kind == .extension, "extension pointers must be reported as extension kind");
        check(target.?.class == DirectExtension, "objectTarget must report the extension class");
    }
    check(objectTarget(ChainedExtension) == null, "class values are not object pointers");
    check(objectTarget(*u32) == null, "scalar pointers are not object pointers");
    check(objectTarget(*anyopaque) == null and objectTarget(?*const anyopaque) == null, "anyopaque pointers are not object pointers");
    check(objectTarget([*]DirectExtension) == null and objectTarget([]DirectExtension) == null, "many pointers and slices are not object pointers");
    check(objectTarget(?[*]const DirectExtension) == null, "optional many pointers are not object pointers");
    check(objectClassOf(?*ChainedExtension) == ChainedExtension, "objectClassOf unwraps optional pointers");
    check(objectClassOf(*u32) == null, "objectClassOf returns null for non-class pointers");
    check(isObjectPointer(*EngineNode) and isObjectPointer(?*ChainedExtension), "isObjectPointer accepts class pointers");
    check(!isObjectPointer(usize) and !isObjectPointer(EngineNode), "isObjectPointer rejects non-pointers");
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

test "object class reflection" {
    comptime comptimeChecks();
}

const classes = @import("../classes/classes.zig");

const hierarchy = @import("hierarchy.zig");
const meta = @import("meta.zig");
