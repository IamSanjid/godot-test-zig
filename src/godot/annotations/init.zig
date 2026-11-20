//! Shared value initializer used by `OnReady.Call` and `Property .init`.

pub fn Init(comptime T: type, comptime p_func: anytype, comptime args: anytype) type {
    const ArgsT = @TypeOf(args);
    if (!reflect.isTuple(ArgsT)) @compileError("Expected a tuple for Init args, found: " ++ @typeName(ArgsT));

    const UnwrappedT = reflect.UnwrappedType(T);
    const func = blk: {
        if (@TypeOf(p_func) == @EnumLiteral()) {
            const func_name = @tagName(p_func);
            if (!std.meta.hasMethod(UnwrappedT, func_name)) {
                @compileError("'" ++ func_name ++ "', doesn't exist in the type: " ++ @typeName(T));
            }
            const f = @field(UnwrappedT, func_name);
            if (@typeInfo(@TypeOf(f)) != .@"fn")
                @compileError("'" ++ func_name ++ "' is not a function.");

            break :blk f;
        }

        if (@typeInfo(@TypeOf(p_func)) != .@"fn") {
            @compileError("The .func is not a function.");
        }

        break :blk p_func;
    };

    const FuncT = @TypeOf(func);
    const fn_info = @typeInfo(FuncT).@"fn";
    const ReturnT = fn_info.return_type orelse
        @compileError("The .func doesn't return the type: " ++ @typeName(T));
    if (ReturnT != T and @typeInfo(T) == .optional and ReturnT != @typeInfo(T).optional.child)
        @compileError("The .func doesn't return the type: " ++ @typeName(T));
    if (fn_info.param_types.len != args.len)
        @compileError(std.fmt.comptimePrint(
            "The func expects {d} arguments, but only {d} is provided.",
            .{ fn_info.param_types.len, args.len },
        ));
    if (fn_info.is_generic) {
        @compileError("The func is a generic function(probably has a comptime argument type) " ++
            "it should be a normal runtime dispatchable function. Use callComptimeArg1 from annotations to wrap them around.");
    }
    const Args = std.meta.ArgsTuple(FuncT);

    return struct {
        pub const InitFor = T;
        pub const arg_func = p_func;
        pub const arg_args = args;

        pub inline fn call(comptime OwnerT: type, comptime Base: type, owner: *OwnerT, base: *Base) T {
            return @call(.auto, func, makeArgs(Args, args, OwnerT, Base, owner, base));
        }
    };
}

pub fn isInit(OtherT: type) bool {
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "InitFor") or
        !@hasDecl(OtherT, "arg_func") or
        !@hasDecl(OtherT, "arg_args")) return false;
    return OtherT == Init(OtherT.InitFor, OtherT.arg_func, OtherT.arg_args);
}

fn makeArgs(
    comptime ArgsT: type,
    comptime args: anytype,
    comptime OwnerT: type,
    comptime Base: type,
    owner: *OwnerT,
    base: *Base,
) ArgsT {
    var rargs: ArgsT = undefined;
    inline for (args, 0..) |arg, i| {
        const Arg = comptime @TypeOf(arg);
        if (comptime Arg == @EnumLiteral()) {
            if (arg == .owner) {
                rargs[i] = owner;
            } else if (arg == .base) {
                rargs[i] = base;
            } else {
                rargs[i] = arg;
            }
        } else if (comptime reflect.isFn(arg)) {
            rargs[i] = callInnerFn(OwnerT, Base, owner, base, arg);
        } else if (comptime @typeInfo(Arg) == .@"struct" and @hasField(Arg, "field")) {
            const field_name = comptime arg.field;
            rargs[i] = @field(owner, field_name);
        } else if (comptime @typeInfo(Arg) == .type and isInit(Arg)) {
            rargs[i] = Arg.call(OwnerT, Base, owner, base);
        } else {
            rargs[i] = arg;
        }
    }
    return rargs;
}

fn callInnerFn(
    comptime OwnerT: type,
    comptime Base: type,
    owner: *OwnerT,
    base: *Base,
    comptime f: anytype,
) reflect.FnReturnType(f).? {
    var iargs: std.meta.ArgsTuple(@TypeOf(f)) = undefined;
    inline for (0..iargs.len) |i| {
        const Pointee = reflect.UnwrappedType(@TypeOf(iargs[i]));
        if (comptime Pointee == OwnerT) {
            iargs[i] = owner;
        } else if (comptime reflect.inheritsFrom(Base, Pointee)) {
            iargs[i] = @ptrCast(base);
        } else {
            @compileError(std.fmt.comptimePrint(
                "Inner function parameter {d} has unsupported type '{s}'; expected a pointer to the owner or to the base (or a parent of it).",
                .{ i, @typeName(@TypeOf(iargs[i])) },
            ));
        }
    }
    return @call(.auto, f, iargs);
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
