//! Reflection/type helpers for the hand-written runtime layer.

const functions = @import("functions.zig");
pub const FunctionOf = functions.FunctionOf;
pub const FunctionReturnType = functions.FunctionReturnType;
pub const FunctionArgsAsTuple = functions.FunctionArgsAsTuple;
pub const FunctionArgsAsTupleSkipFirst = functions.FunctionArgsAsTupleSkipFirst;

const hierarchy = @import("hierarchy.zig");
pub const inheritsFrom = hierarchy.inheritsFrom;
pub const extendsType = hierarchy.extendsType;

const base = @import("base.zig");
pub const BaseField = base.BaseField;
pub const findBaseField = base.findBaseField;
pub const findBaseFieldFor = base.findBaseFieldFor;
pub const basePointer = base.basePointer;

const objects = @import("objects.zig");
pub const isRefCounted = objects.isRefCounted;
pub const isRefCountedPointer = objects.isRefCountedPointer;
pub const ObjectKind = objects.ObjectKind;
pub const ObjectTarget = objects.ObjectTarget;
pub const isEngineObjectClass = objects.isEngineObjectClass;
pub const isExtensionClass = objects.isExtensionClass;
pub const isClassType = objects.isClassType;
pub const objectTarget = objects.objectTarget;
pub const objectClassOf = objects.objectClassOf;
pub const isObjectPointer = objects.isObjectPointer;

const extension = @import("extension.zig");
pub const EngineBaseType = extension.EngineBaseType;
pub const engineBasePointer = extension.engineBasePointer;

const meta = @import("meta.zig");
pub const isTuple = meta.isTuple;
pub const isOpaque = meta.isOpaque;
pub const isNormalStruct = meta.isNormalStruct;
pub const isLikelyNamespace = meta.isLikelyNamespace;
pub const isSelfType = meta.isSelfType;
pub const className = meta.className;
pub const isSelfPtrType = meta.isSelfPtrType;
pub const hasAllDefaults = meta.hasAllDefaults;
pub const isOptionalPointer = meta.isOptionalPointer;
pub const isNormalFunction = meta.isNormalFunction;
pub const ValueType = meta.ValueType;
pub const isFn = meta.isFn;
pub const FnReturnType = meta.FnReturnType;

const defaults = @import("defaults.zig");
pub const initFieldsDefault = defaults.initFieldsDefault;

comptime {
    // Keep the hierarchy/object/extension helpers analyzed (and their
    // compile-only checks live) even while no runtime caller references them
    // directly. `Variant` and registration build on these helpers; a plain
    // `zig build` must still catch a broken contract here.
    hierarchy.comptimeSelfCheck();
    objects.comptimeSelfCheck();
    extension.comptimeSelfCheck();
}
