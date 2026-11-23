/// If `T` has a public declaration as InitCallback(T, foo), that foo will be called during this type creation.
///
/// If `foo` is a member function (first argument is T / *T / *const T) it must return void or !void.
/// If `foo` is a "static" function it must return T or !T.
///
/// Besides `self`, `foo` may take a std.mem.Allocator (the one used to create it),
/// a *Base pointer, or both, in any order (each at most once).
pub fn InitCallback(comptime T: type, comptime method: anytype) type {
    if (!reflect.isExtensionClass(T)) @compileError("'" ++ @typeName(T) ++ "' is not an extension class type.");

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

    const max_params = if (is_member) 3 else 2;
    if (params.len > max_params) @compileError("Too many parameters (*self, Allocator, *Base are the only options).");

    // Validate the non-self params.
    const first_extra = if (is_member) 1 else 0;
    comptime var seen_allocator = false;
    comptime var seen_base = false;
    inline for (params[first_extra..]) |maybe_p| {
        const P = maybe_p.?;
        if (P == Allocator) {
            if (seen_allocator) @compileError("Allocator parameter given twice.");
            seen_allocator = true;
        } else if (P == *Extends) {
            if (seen_base) @compileError("Base parameter given twice.");
            seen_base = true;
        } else {
            @compileError("Unsupported parameter type '" ++ @typeName(P) ++ "', expected std.mem.Allocator or *" ++ @typeName(Extends));
        }
    }

    // Validate the return type (error unions allowed).
    const Ret = fn_info.return_type.?;
    const Payload = switch (@typeInfo(Ret)) {
        .error_union => |eu| eu.payload,
        else => Ret,
    };
    if (is_member) {
        if (Payload != void) @compileError("A member init function must return void or !void.");
    } else {
        if (Payload != T) @compileError("A static init function must return " ++ @typeName(T) ++ " or !" ++ @typeName(T) ++ ".");
    }

    const Args = std.meta.ArgsTuple(MethodT);

    return struct {
        pub const InitFor = T;
        pub const TExtends = Extends;
        pub const init_method = method;
        pub const init_is_member = is_member;
        pub const returns_error = @typeInfo(Ret) == .error_union;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.init_callback;

        pub fn makeArgs(self: *T, allocator: Allocator, base: *Extends) Args {
            var args: Args = undefined;
            inline for (params, 0..) |maybe_p, i| {
                const P = maybe_p.?;
                if (comptime is_member and i == 0) {
                    args[i] = self;
                } else if (comptime P == Allocator) {
                    args[i] = allocator;
                } else {
                    args[i] = base; // validated above: must be *Extends
                }
            }
            return args;
        }
    };
}

/// For member markers and value-returning static markers; a no-op if T has no marker.
pub fn callInitCallback(
    comptime T: type,
    comptime B: type,
    self: *T,
    base: *B,
    allocator: std.mem.Allocator,
) !void {
    const Marker = findInitCallback(T) orelse return;
    comptime if (B != Marker.TExtends)
        @compileError("Base type mismatch: expected '" ++ @typeName(Marker.TExtends) ++
            "', got '" ++ @typeName(B) ++ "'.");

    const args = Marker.makeArgs(self, allocator, base);

    if (comptime Marker.init_is_member) {
        if (comptime Marker.returns_error) {
            try @call(.auto, Marker.init_method, args);
        } else {
            @call(.auto, Marker.init_method, args);
        }
    } else {
        // Static function: returns T or !T, which becomes the new value of `self`.
        self.* = if (comptime Marker.returns_error)
            try @call(.auto, Marker.init_method, args)
        else
            @call(.auto, Marker.init_method, args);
    }
}

/// Returns the single Init marker declared on `T`, or null if there is none.
/// Rejects duplicate.
fn findInitCallback(comptime T: type) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type, found " ++ @typeName(T));

    comptime var found: ?type = null;
    inline for (info.@"struct".decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime isInitCallbackMarker(Decl)) {
            if (found != null) {
                @compileError("'" ++ @typeName(T) ++ "' has more than one Init marker; only one is allowed.");
            }
            if (Decl.InitFor != T) {
                @compileError("Init marker '" ++ decl_name ++ "' was built for '" ++ @typeName(Decl.InitFor) ++
                    "', not '" ++ @typeName(T) ++ "'.");
            }
            found = Decl;
        }
    }
    return found;
}

/// True if `Decl` is a type produced by `Init(...)`.
fn isInitCallbackMarker(comptime Decl: anytype) bool {
    if (@TypeOf(Decl) != type) return false;
    if (!marker_kind.is(Decl, .init_callback)) return false;
    if (@typeInfo(Decl) != .@"struct") return false;
    if (!@hasDecl(Decl, "InitFor") or !@hasDecl(Decl, "init_method")) return false;
    return Decl == InitCallback(Decl.InitFor, Decl.init_method);
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
const marker_kind = @import("marker.zig");
