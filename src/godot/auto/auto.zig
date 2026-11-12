const functions = @import("functions.zig");
pub const FunctionOf = functions.FunctionOf;
pub const FunctionReturnType = functions.FunctionReturnType;
pub const FunctionArgsAsTuple = functions.FunctionArgsAsTuple;
pub const FunctionArgsAsTupleSkipFirst = functions.FunctionArgsAsTupleSkipFirst;

const annotations = @import("annotations.zig");

const inheritance = @import("inheritance.zig");
pub const inheritsFrom = inheritance.inheritsFrom;
