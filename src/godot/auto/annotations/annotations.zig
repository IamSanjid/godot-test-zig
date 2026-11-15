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

const notification_callback = @import("notification_callback.zig");
pub const NotificationCallback = notification_callback.NotificationCallback;
pub const callNotificationCallback = notification_callback.callNotificationCallback;

pub fn initAnnotFieldsDefault(comptime T: type, comptime B: type, child: *T, b: *B) void {
    _ = b;
    inline for (comptime on_ready.findOnReadyFieldNames(T)) |field| {
        @field(child, field) = .{};
    }
}
