//! Extension-class to engine-base resolution.

/// The ultimate opaque engine object class behind class type `T`.
///
/// - engine object classes return themselves;
/// - extension classes walk their `Extends` chain and require a
///   `Base(<direct parent>)` marker field at every extension level. The walk
///   stops at the terminal engine class, which the engine owns and which
///   therefore needs no marker.
///
/// Compile-errors when `T` is not a class type, or when an extension level has
/// no matching Base marker (with a hint when a marker points at the wrong type).
pub fn EngineBaseType(comptime T: type) type {
    @setEvalBranchQuota(2000);
    if (comptime objects.isEngineObjectClass(T)) return T;
    if (comptime !objects.isExtensionClass(T)) {
        @compileError("'" ++ @typeName(T) ++
            "' has an invalid Extends chain; an extension class must extend another extension class or an engine object class.");
    }

    const Parent = hierarchy.extendsType(T) orelse @compileError("'" ++ @typeName(T) ++ "' has a malformed Extends declaration.");
    requireExtensionBase(T, Parent);
    return EngineBaseType(Parent);
}

/// Borrowed ultimate engine object behind the class instance `instance`.
///
/// Engine object classes return `instance` itself. Extension classes walk the
/// Base marker chain: every extension level's marker points at its direct parent
/// instance, so the final step yields the engine object the engine owns.
///
/// The returned pointer aliases existing storage; no ownership changes. The
/// chain is validated at compile time by `EngineBaseType`.
pub fn engineBasePointer(comptime T: type, instance: *const T) *EngineBaseType(T) {
    const root: *T = @constCast(instance);
    if (comptime objects.isEngineObjectClass(T)) {
        return root;
    } else {
        return @ptrCast(@alignCast(engineBasePointerStep(T, @ptrCast(root))));
    }
}

/// Compile-time check: every extension level must declare a Base marker for its
/// direct parent. Produces a pointed compile error otherwise.
fn requireExtensionBase(comptime T: type, comptime Parent: type) void {
    if (comptime base.findBaseFieldFor(T, Parent) != null) return;

    if (comptime base.findBaseField(T)) |other| {
        @compileError("Extension class '" ++ @typeName(T) ++ "' declares base marker field '" ++ other.name ++
            "' for '" ++ @typeName(other.base_type) ++ "', but its Extends is '" ++ @typeName(Parent) ++
            "'; the Base marker must point at the direct parent class.");
    }
    @compileError("Extension class '" ++ @typeName(T) ++ "' has no Base(" ++ @typeName(Parent) ++
        ") marker field; declare one (for example `base: annotations.Base(" ++ @typeName(Parent) ++
        ")`) so its engine base can be resolved.");
}

/// One step of the runtime Base marker walk. `T` is the current class type.
fn engineBasePointerStep(comptime T: type, instance: *anyopaque) *anyopaque {
    if (comptime objects.isEngineObjectClass(T)) {
        return instance;
    } else {
        const Parent = hierarchy.extendsType(T) orelse @compileError("'" ++ @typeName(T) ++ "' has a malformed Extends declaration.");
        const typed: *const T = @ptrCast(@alignCast(instance));
        const parent = base.basePointer(T, Parent, typed) orelse unreachable;
        return engineBasePointerStep(Parent, @ptrCast(parent));
    }
}

const base = @import("base.zig");
const hierarchy = @import("hierarchy.zig");
const objects = @import("objects.zig");
