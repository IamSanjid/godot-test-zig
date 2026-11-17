/// If `T` has a public declaration as DeinitCallback(T, foo), that foo will be called during this type destruction/free.
///
/// `foo` must be a member function and may or may not accept a std.mem.Allocator. And must return void.
pub fn DeinitCallback(comptime T: type, comptime method: anytype) type {
    if (!reflect.isEngineClass(T)) @compileError("'" ++ @typeName(T) ++ "' is not an Engine class type.");

    const MethodT = @TypeOf(method);
    const type_info = @typeInfo(MethodT);
    if (type_info != .@"fn") @compileError("Needs a function, found: " ++ @typeName(MethodT));
    const fn_info = type_info.@"fn";
    if (fn_info.is_generic) @compileError("Function cannot be generic.");

    const Extends = T.Extends;
    const Allocator = std.mem.Allocator;
    const params = fn_info.param_types;

    const is_member = blk: {
        if (params.len == 0) break :blk false;
        const P0 = params[0].?;
        if (P0 == T or P0 == *const T)
            @compileError("The function needs to accept a *" ++
                @typeName(T) ++ ", but it accepts " ++ @typeName(P0));
        break :blk P0 == *T;
    };

    if (!is_member) @compileError("The function is not a member function of: " ++ @typeName(T));

    const max_params = 2;
    if (params.len > max_params) @compileError("Too many parameters (*self, Allocator).");

    if (params.len == 2 and params[1].? != Allocator) {
        @compileError("Unsupported parameter type expected std.mem.Allocator, found: " ++ @typeName(params[1].?));
    }

    const Ret = fn_info.return_type.?;
    if (Ret != void) @compileError("A deinit callback must return a void found: " ++ @typeName(Ret));

    const Args = std.meta.ArgsTuple(MethodT);

    return struct {
        pub const DeinitFor = T;
        pub const TExtends = Extends;
        pub const deinit_method = method;

        pub fn makeArgs(self: *T, allocator: Allocator) Args {
            var args: Args = undefined;
            inline for (params, 0..) |maybe_p, i| {
                const P = maybe_p.?;
                if (comptime is_member and i == 0) {
                    args[i] = self;
                } else if (comptime P == Allocator) {
                    args[i] = allocator;
                }
            }
            return args;
        }
    };
}

/// Runs the `DeinitCallback` marker declared on `T`, if any. A no-op otherwise.
/// Does NOT free `self`; the caller still destroys it afterwards.
pub fn callDeinitCallback(
    comptime T: type,
    comptime B: type,
    self: *T,
    allocator: std.mem.Allocator,
) void {
    const MarkerOpt = comptime findDeinitCallback(T);
    if (MarkerOpt == null) return;
    const Marker = MarkerOpt.?;
    comptime if (B != Marker.TExtends)
        @compileError("Base type mismatch: expected '" ++ @typeName(Marker.TExtends) ++
            "', got '" ++ @typeName(B) ++ "'.");

    @call(.auto, Marker.deinit_method, Marker.makeArgs(self, allocator));
}

/// Returns the single Deinit marker declared on `T`, or null if there is none.
/// Rejects duplicate.
fn findDeinitCallback(comptime T: type) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type, found " ++ @typeName(T));

    comptime var found: ?type = null;
    inline for (info.@"struct".decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime isDeinitCallbackMarker(Decl)) {
            if (found != null) {
                @compileError("'" ++ @typeName(T) ++ "' has more than one DeinitCallback marker; only one is allowed.");
            }
            if (Decl.DeinitFor != T) {
                @compileError("DeinitCallback marker '" ++ decl_name ++ "' was built for '" ++ @typeName(Decl.DeinitFor) ++
                    "', not '" ++ @typeName(T) ++ "'.");
            }
            found = Decl;
        }
    }
    return found;
}

/// True if `Decl` is a type produced by `DeinitCallback(...)`.
fn isDeinitCallbackMarker(comptime Decl: anytype) bool {
    if (@TypeOf(Decl) != type) return false;
    if (@typeInfo(Decl) != .@"struct") return false;
    if (!@hasDecl(Decl, "DeinitFor") or !@hasDecl(Decl, "deinit_method")) return false;
    return Decl == DeinitCallback(Decl.DeinitFor, Decl.deinit_method);
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
