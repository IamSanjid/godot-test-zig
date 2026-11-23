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

/// True when `T` is a class type that inherits `Node`; object pointers and
/// non-class types return false.
pub fn isNodeClass(comptime T: type) bool {
    return isClassType(T) and hierarchy.inheritsFrom(T, classes.core.Node);
}

/// True when `T` is a class type that inherits `Resource`; object pointers and
/// non-class types return false.
pub fn isResourceClass(comptime T: type) bool {
    return isClassType(T) and hierarchy.inheritsFrom(T, classes.core.Resource);
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

const classes = @import("../classes/classes.zig");
const hierarchy = @import("hierarchy.zig");
const meta = @import("meta.zig");
