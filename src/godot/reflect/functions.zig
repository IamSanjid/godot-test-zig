fn FunctionTOf(comptime Of: type, comptime function: @EnumLiteral()) type {
    const function_name = @tagName(function);
    if (!@hasDecl(Of, function_name)) {
        @compileError("'" ++ function_name ++ "' method not found in '" ++ @typeName(Of) ++ "' binding type");
    }

    const FunctionT = @TypeOf(@field(Of, function_name));
    if (@typeInfo(FunctionT) != .@"fn") {
        @compileError("'" ++ function_name ++ "' is not a function in '" ++ @typeName(Of) ++ "' binding type");
    }
    return FunctionT;
}

pub fn FunctionOf(comptime Of: type, comptime function: @EnumLiteral()) FunctionTOf(Of, function) {
    return @field(Of, @tagName(function));
}

pub fn FunctionReturnType(comptime function: anytype) type {
    const T = @TypeOf(function);
    const type_info = @typeInfo(T);
    if (type_info == .type) {
        const fn_type: type = function;
        const fn_info = @typeInfo(fn_type);
        if (fn_info != .@"fn") {
            @compileError("Expected a function type but found: " ++ @typeName(fn_type));
        }
        return fn_info.@"fn".return_type orelse void;
    }
    return FunctionReturnType(T);
}

pub fn FunctionArgsAsTuple(comptime function: anytype) type {
    const T = @TypeOf(function);
    const type_info = @typeInfo(T);
    if (type_info == .type) {
        const FnT: type = function;
        const fn_info = @typeInfo(FnT);
        if (fn_info != .@"fn") {
            @compileError("Expected a function type but found: " ++ @typeName(FnT));
        }
        const fn_type = fn_info.@"fn";
        var tuple_types: [fn_type.param_types.len]type = undefined;
        for (fn_type.param_types, 0..) |pt, i| {
            tuple_types[i] = pt orelse
                @compileError("Parameter Type needs well defined type but found null for " ++ @typeName(FnT) ++ ", param no: " ++ i);
        }
        return @Tuple(&tuple_types);
    }
    return FunctionArgsAsTuple(T);
}

pub fn FunctionArgsAsTupleSkipFirst(comptime function: anytype) type {
    const T = @TypeOf(function);
    const type_info = @typeInfo(T);
    if (type_info == .type) {
        const FnT: type = function;
        const fn_info = @typeInfo(FnT);
        if (fn_info != .@"fn") {
            @compileError("Expected a function type but found: " ++ @typeName(FnT));
        }
        const fn_type = fn_info.@"fn";
        if (fn_type.param_types.len == 0 or fn_type.param_types.len == 1) {
            return @Tuple(&[_]type{});
        }
        var tuple_types: [fn_type.param_types.len - 1]type = undefined;
        for (fn_type.param_types[1..], 0..) |pt, i| {
            tuple_types[i] = pt orelse
                @compileError("Parameter Type needs well defined type but found null for " ++ @typeName(FnT) ++ ", param no: " ++ i + 1);
        }
        return @Tuple(&tuple_types);
    }
    return FunctionArgsAsTupleSkipFirst(T);
}

const std = @import("std");
