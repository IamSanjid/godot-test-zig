const functions = @import("functions.zig");
pub const FunctionOf = functions.FunctionOf;
pub const FunctionReturnType = functions.FunctionReturnType;
pub const FunctionArgsAsTuple = functions.FunctionArgsAsTuple;
pub const FunctionArgsAsTupleSkipFirst = functions.FunctionArgsAsTupleSkipFirst;

pub const annot = @import("annotations/annotations.zig");

const inheritance = @import("inheritance.zig");
pub const inheritsFrom = inheritance.inheritsFrom;
pub const isEngineClass = inheritance.isEngineClass;

const meta = @import("meta.zig");
pub const isTuple = meta.isTuple;
pub const isOpaque = meta.isOpaque;
pub const isNormalStruct = meta.isNormalStruct;
pub const isNamespace = meta.isNamespace;
pub const isSelfType = meta.isSelfType;
pub const isSelfPtrType = meta.isSelfPtrType;
pub const hasAllDefaults = meta.hasAllDefaults;
pub const isNormalFunction = meta.isNormalFunction;
pub const ValueType = meta.ValueType;
pub const isFn = meta.isFn;
pub const FnReturnType = meta.FnReturnType;

pub fn initFieldsDefault(comptime T: type, child: *T) void {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("Exptected struct, found: " ++ @typeName(T));
    const struct_info = type_info.@"struct";
    inline for (struct_info.field_names, struct_info.field_attrs, struct_info.field_types) |field, attr, F| {
        if (comptime attr.default_value_ptr != null) {
            @field(child, field) = attr.defaultValue(F) orelse unreachable;
        }
    }
}

pub fn callComptimeArg1(comptime f: anytype, comptime arg: anytype) fn () (FnReturnType(f) orelse void) {
    return struct {
        fn wrapper() (FnReturnType(f) orelse void) {
            return f(arg);
        }
    }.wrapper;
}
