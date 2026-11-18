/// `strategy` is .{ .node = comptime string literal, or
/// Order matters, it's a tuple so first tuple value should be a method decl, and 2nd one is another tuple for args
/// .call = .{ func, .{ "", .{ .field = comptime owner field name }, .owner(pases owner as *ptr), .base(pases base as *ptr) } } }
/// .node varaint requires a field to be marked as `Base`.
pub fn OnReady(comptime T: type, comptime strategy: anytype) type {
    const StrategyT = @TypeOf(strategy);
    if (@hasField(StrategyT, "node")) {
        return OnReadyNode(T, strategy.node);
    } else if (@hasField(StrategyT, "call")) {
        const CallT = @TypeOf(strategy.call);
        if (!reflect.isTuple(CallT)) @compileError("Expected a tuple for .call strategy, found: " ++ @typeName(CallT));

        const func = strategy.call[0];
        const args = if (strategy.call.len > 1) strategy.call[1] else .{};
        return OnReadyCall(T, func, args);
    } else @compileError("Not supported strategy");
}

pub fn OnReadyNode(comptime T: type, comptime p_node_path: [:0]const u8) type {
    if (!reflect.inheritsFrom(reflect.ValueType(T), classes.core.Node)) {
        @compileError("Type: " ++ @typeName(T) ++ ", doesn't extend a Node, it cannot be attached to another Node");
    }

    const ValueT = if (reflect.isOpaque(T)) *T else T;

    return struct {
        pub const ForT = T;
        pub const node_path = p_node_path;
        value: ?ValueT = null,

        const Self = @This();

        pub fn isSelf(OtherT: type) bool {
            if (@typeInfo(OtherT) != .@"struct") return false;
            if (!@hasDecl(OtherT, "isSelf") or
                !@hasDecl(OtherT, "ForT") or
                !@hasDecl(OtherT, "node_path") or
                !@hasDecl(OtherT, "init")) return false;
            return OtherT == OnReadyNode(OtherT.ForT, OtherT.node_path);
        }

        /// No deinitialization needed, it's cached.
        pub fn nodePath() builtins.NodePath {
            return .fromComptimeLatin1(node_path);
        }

        pub fn init(comptime OwnerT: type, comptime Base: type, owner: *OwnerT, base: *Base) Self {
            _ = owner;
            const value = if (base.getNode(nodePath())) |v| v.downcast(T) else null;
            return .{ .value = value };
        }

        /// unwraps
        pub fn get(self: *const Self) ValueT {
            return self.value orelse if (is_runtime_safety)
                @panic("OnReady<" ++ @typeName(T) ++ "> used before _ready or its init failed")
            else
                unreachable;
        }

        pub fn getPtr(self: *Self) ?*ValueT {
            if (self.value) |*v| return v;
            return null;
        }

        pub fn getPtrConst(self: *const Self) ?*const ValueT {
            if (self.value) |*v| return v;
            return null;
        }
    };
}

pub fn OnReadyCall(comptime T: type, comptime p_func: anytype, comptime args: anytype) type {
    const ArgsT = @TypeOf(args);
    if (!reflect.isTuple(ArgsT)) @compileError("Expected a tuple for .call strategy args, found: " ++ @typeName(ArgsT));

    const func = blk: {
        if (@TypeOf(p_func) == @EnumLiteral()) {
            const func_name = @tagName(p_func);
            if (!std.meta.hasMethod(T, func_name)) {
                @compileError("'" ++ func_name ++ "', doesn't exist in the type: " ++ @typeName(T));
            }
            const f = @field(T, func_name);
            if (@typeInfo(@TypeOf(f)) != .@"fn")
                @compileError("'" ++ func_name ++ "' is not a function.");

            break :blk f;
        }

        if (@typeInfo(@TypeOf(p_func)) != .@"fn") {
            @compileError("The .func is not a function.");
        }

        break :blk p_func;
    };

    const ValueT = if (reflect.isOpaque(T)) *T else T;

    const FuncT = @TypeOf(func);
    const fn_info = @typeInfo(FuncT).@"fn";
    const ReturnT = fn_info.return_type orelse
        @compileError("The .func doesn't return the type: " ++ @typeName(ValueT));
    if (ReturnT != ValueT)
        @compileError("The .func doesn't return the type: " ++ @typeName(ValueT));
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
        pub const ForT = T;
        pub const arg_func = p_func;
        pub const arg_args = args;

        value: ?ValueT = null,

        const Self = @This();

        pub fn isSelf(OtherT: type) bool {
            if (@typeInfo(OtherT) != .@"struct") return false;
            if (!@hasDecl(OtherT, "isSelf") or
                !@hasDecl(OtherT, "ForT") or
                !@hasDecl(OtherT, "arg_func") or
                !@hasDecl(OtherT, "arg_args")) return false;
            return OtherT == OnReadyCall(OtherT.ForT, OtherT.arg_func, OtherT.arg_args);
        }

        pub fn init(comptime OwnerT: type, comptime Base: type, owner: *OwnerT, base: *Base) Self {
            return .{ .value = @call(.auto, func, makeArgs(OwnerT, Base, owner, base)) };
        }

        fn makeArgs(comptime OwnerT: type, comptime Base: type, owner: *OwnerT, base: *Base) Args {
            var rargs: Args = undefined;
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
                const Pointee = reflect.ValueType(@TypeOf(iargs[i]));
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

        /// unwraps
        pub fn get(self: *const Self) ValueT {
            return self.value orelse if (is_runtime_safety)
                @panic("OnReady<" ++ @typeName(T) ++ "> used before _ready or its init failed")
            else
                unreachable;
        }

        pub fn getPtr(self: *Self) ?*ValueT {
            if (self.value) |*v| return v;
            return null;
        }

        pub fn getPtrConst(self: *const Self) ?*const ValueT {
            if (self.value) |*v| return v;
            return null;
        }
    };
}

pub fn initOnReadyFields(comptime T: type, comptime B: type, owner: *T, base: *B) void {
    inline for (comptime findOnReadyFieldNames(T)) |field| {
        @field(owner, field) = .init(T, B, owner, base);
    }
}

pub fn findOnReadyFieldNames(comptime T: type) []const [:0]const u8 {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") @compileError("Exptected struct, found: " ++ @typeName(T));
        const info = type_info.@"struct";
        var names: [info.field_names.len][:0]const u8 = undefined;
        var n: usize = 0;
        for (info.field_names, info.field_types) |name, F| {
            if (reflect.isNormalStruct(F) and @hasDecl(F, "isSelf")) {
                const isSelf = @field(F, "isSelf");
                const is_self_type_info = @typeInfo(@TypeOf(isSelf));
                if (is_self_type_info != .@"fn") continue;
                const fn_info = is_self_type_info.@"fn";
                if (fn_info.param_types.len == 0) continue;
                const self_param = fn_info.param_types[0] orelse continue;
                if (self_param != type) continue;
                if (!isSelf(F)) continue;
                names[n] = name;
                n += 1;
            }
        }
        const out = names[0..n].*;
        return &out;
    }
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
const classes = @import("../classes/classes.zig");
const builtins = @import("../builtins/builtins.zig");

const is_runtime_safety = @import("builtin").mode.runtimeSafety();
