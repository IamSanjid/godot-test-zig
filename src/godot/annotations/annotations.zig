//! Opt-in marker annotations (Base, OnReady, Init/Deinit/Notification callbacks).

const base = @import("base.zig");
pub const Base = base.Base;
pub const initBase = base.initBase;

const init_callback = @import("init_callback.zig");
pub const InitCallback = init_callback.InitCallback;
pub const callInitCallback = init_callback.callInitCallback;

const deinit_callback = @import("deinit_callback.zig");
pub const DeinitCallback = deinit_callback.DeinitCallback;
pub const callDeinitCallback = deinit_callback.callDeinitCallback;

const on_ready = @import("on_ready.zig");
pub const OnReady = on_ready.OnReady;
pub const OnReadyNode = on_ready.OnReadyNode;
pub const OnReadyCall = on_ready.OnReadyCall;
pub const initOnReadyFields = on_ready.initOnReadyFields;
pub const findOnReadyFieldNames = on_ready.findOnReadyFieldNames;

const notification_callback = @import("notification_callback.zig");
pub const NotificationCallback = notification_callback.NotificationCallback;
pub const callNotificationCallback = notification_callback.callNotificationCallback;

const override = @import("override.zig");
pub const Override = override.Override;

pub fn initAnnotFieldsDefault(comptime T: type, comptime B: type, child: *T, b: *B) void {
    _ = b;
    inline for (comptime on_ready.findOnReadyFieldNames(T)) |field| {
        @field(child, field) = .{};
    }
}

/// Wraps a comptime-argument function so it can be used as a normal runtime
/// dispatchable function, e.g. for `.call` strategies that need comptime args.
pub fn callComptimeArg1(comptime f: anytype, comptime arg: anytype) fn () (reflect.FnReturnType(f) orelse void) {
    return struct {
        fn wrapper() (reflect.FnReturnType(f) orelse void) {
            return f(arg);
        }
    }.wrapper;
}

const reflect = @import("../reflect/reflect.zig");
