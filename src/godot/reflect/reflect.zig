//! Reflection/type helpers for the hand-written runtime layer.

const functions = @import("functions.zig");
pub const FunctionOf = functions.FunctionOf;
pub const FunctionReturnType = functions.FunctionReturnType;
pub const FunctionArgsAsTuple = functions.FunctionArgsAsTuple;
pub const FunctionArgsAsTupleSkipFirst = functions.FunctionArgsAsTupleSkipFirst;

const inheritance = @import("inheritance.zig");
pub const inheritsFrom = inheritance.inheritsFrom;
pub const isEngineClass = inheritance.isEngineClass;
pub const isRefCounted = inheritance.isRefCounted;
pub const isRefCountedPointer = inheritance.isRefCountedPointer;

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
