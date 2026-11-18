/// If `T` has a public declaration as NotificationCallback(T, foo), that foo will be called when notification is received.
///
/// `foo` must be a member function and not accept any arguments. And must return void.
pub fn NotificationCallback(comptime T: type, comptime method: anytype) type {
    if (!reflect.isExtensionClass(T)) @compileError("'" ++ @typeName(T) ++ "' is not an extension class type.");

    const MethodT = @TypeOf(method);
    const type_info = @typeInfo(MethodT);
    if (type_info != .@"fn") @compileError("Needs a function, found: " ++ @typeName(MethodT));
    const fn_info = type_info.@"fn";
    if (fn_info.is_generic) @compileError("Function cannot be generic.");

    const Extends = T.Extends;
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

    const max_params = 3;
    if (params.len != max_params) @compileError("The function needs to accept 3 parameters (*self, p_what, p_reversed).");

    if (fn_info.param_types[1].? != i32) @compileError("A notification callback must accept p_what: i32, found: " ++ @typeName(fn_info.param_types[1].?));
    if (fn_info.param_types[2].? != bool) @compileError("A notification callback must accept p_reversed: bool, found: " ++ @typeName(fn_info.param_types[2].?));

    const Ret = fn_info.return_type.?;
    if (Ret != void) @compileError("A notification callback must return a void found: " ++ @typeName(Ret));

    const Args = std.meta.ArgsTuple(MethodT);

    return struct {
        pub const NotificationFor = T;
        pub const TExtends = Extends;
        pub const notification_method = method;

        pub fn makeArgs(self: *T, p_what: i32, p_reversed: bool) Args {
            return .{ self, p_what, p_reversed };
        }
    };
}

/// Runs the `NotificationCallback` marker declared on `T`, if any. A no-op otherwise.
/// Does NOT free `self`; the caller still destroys it afterwards.
pub fn callNotificationCallback(
    comptime T: type,
    comptime B: type,
    self: *T,
    p_what: i32,
    p_reversed: bool,
) void {
    const Marker = findNotificationCallback(T) orelse return;
    comptime if (B != Marker.TExtends)
        @compileError("Base type mismatch: expected '" ++ @typeName(Marker.TExtends) ++
            "', got '" ++ @typeName(B) ++ "'.");

    @call(.auto, Marker.notification_method, Marker.makeArgs(self, p_what, p_reversed));
}

/// Returns the single Notification marker declared on `T`, or null if there is none.
/// Rejects duplicate.
fn findNotificationCallback(comptime T: type) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("Expected struct type, found " ++ @typeName(T));

    comptime var found: ?type = null;
    inline for (info.@"struct".decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime isNotificationCallbackMarker(Decl)) {
            if (found != null) {
                @compileError("'" ++ @typeName(T) ++ "' has more than one NotificationCallback marker; only one is allowed.");
            }
            if (Decl.NotificationFor != T) {
                @compileError("NotificationCallback marker '" ++ decl_name ++ "' was built for '" ++ @typeName(Decl.NotificationFor) ++
                    "', not '" ++ @typeName(T) ++ "'.");
            }
            found = Decl;
        }
    }
    return found;
}

/// True if `Decl` is a type produced by `NotificationCallback(...)`.
fn isNotificationCallbackMarker(comptime Decl: anytype) bool {
    if (@TypeOf(Decl) != type) return false;
    if (@typeInfo(Decl) != .@"struct") return false;
    if (!@hasDecl(Decl, "NotificationFor") or !@hasDecl(Decl, "notification_method")) return false;
    return Decl == NotificationCallback(Decl.NotificationFor, Decl.notification_method);
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
