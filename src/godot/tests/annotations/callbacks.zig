//! `InitCallback` / `DeinitCallback` / `NotificationCallback` marker identity
//! and discovery through the public lifecycle call helpers.

const CallbackFixture = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},

    init_calls: u32 = 0,
    deinit_calls: u32 = 0,
    notification_what: i32 = 0,
    notification_reversed: bool = false,

    pub const Init = godot.annotations.InitCallback(CallbackFixture, onInit);
    pub const Deinit = godot.annotations.DeinitCallback(CallbackFixture, onDeinit);
    pub const Notification = godot.annotations.NotificationCallback(CallbackFixture, onNotification);

    fn onInit(self: *@This()) void {
        self.init_calls += 1;
    }

    fn onDeinit(self: *@This()) void {
        self.deinit_calls += 1;
    }

    fn onNotification(self: *@This(), p_what: i32, p_reversed: bool) void {
        self.notification_what = p_what;
        self.notification_reversed = p_reversed;
    }
};

/// Payload-shaped declarations without the marker kinds: discovery must skip
/// every one of them, so the call helpers stay no-ops.
const LookalikeClass = struct {
    init_calls: u32 = 0,
    deinit_calls: u32 = 0,
    notification_calls: u32 = 0,

    pub const FakeInit = struct {
        pub const InitFor = LookalikeClass;
        pub const TExtends = void;
        pub const init_method = LookalikeClass.onInit;
    };
    pub const FakeDeinit = struct {
        pub const DeinitFor = LookalikeClass;
        pub const TExtends = void;
        pub const deinit_method = LookalikeClass.onDeinit;
    };
    pub const FakeNotification = struct {
        pub const NotificationFor = LookalikeClass;
        pub const TExtends = void;
        pub const notification_method = LookalikeClass.onNotification;
    };

    fn onInit(self: *LookalikeClass) void {
        self.init_calls += 1;
    }

    fn onDeinit(self: *LookalikeClass) void {
        self.deinit_calls += 1;
    }

    fn onNotification(self: *LookalikeClass, _: i32, _: bool) void {
        self.notification_calls += 1;
    }
};

fn checkCallbackMarkers() void {
    if (comptime !godot.annotations.marker.is(CallbackFixture.Init, .init_callback))
        @compileError("InitCallback markers must declare marker.Kind.init_callback");
    if (comptime !godot.annotations.marker.is(CallbackFixture.Deinit, .deinit_callback))
        @compileError("DeinitCallback markers must declare marker.Kind.deinit_callback");
    if (comptime !godot.annotations.marker.is(CallbackFixture.Notification, .notification_callback))
        @compileError("NotificationCallback markers must declare marker.Kind.notification_callback");

    if (comptime godot.annotations.marker.is(CallbackFixture.Init, .deinit_callback))
        @compileError("callback markers must not identify as another callback family");
    if (comptime godot.annotations.marker.kindOf(LookalikeClass.FakeInit) != null)
        @compileError("an InitCallback lookalike must not declare an annotation marker");
    if (comptime godot.annotations.marker.kindOf(LookalikeClass.FakeDeinit) != null)
        @compileError("a DeinitCallback lookalike must not declare an annotation marker");
    if (comptime godot.annotations.marker.kindOf(LookalikeClass.FakeNotification) != null)
        @compileError("a NotificationCallback lookalike must not declare an annotation marker");
}

comptime {
    checkCallbackMarkers();
}

test "callback markers are discovered by their kind" {
    comptime checkCallbackMarkers();

    var fixture: CallbackFixture = .{};
    const base: *CallbackFixture.Extends = undefined;
    try godot.annotations.callInitCallback(CallbackFixture, CallbackFixture.Extends, &fixture, base, std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), fixture.init_calls);

    godot.annotations.callDeinitCallback(CallbackFixture, CallbackFixture.Extends, &fixture, std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), fixture.deinit_calls);

    godot.annotations.callNotificationCallback(CallbackFixture, CallbackFixture.Extends, &fixture, 7, true);
    try std.testing.expectEqual(@as(i32, 7), fixture.notification_what);
    try std.testing.expect(fixture.notification_reversed);

    var lookalike: LookalikeClass = .{};
    var lookalike_base: void = {};
    try godot.annotations.callInitCallback(LookalikeClass, void, &lookalike, &lookalike_base, std.testing.allocator);
    godot.annotations.callDeinitCallback(LookalikeClass, void, &lookalike, std.testing.allocator);
    godot.annotations.callNotificationCallback(LookalikeClass, void, &lookalike, 1, false);
    try std.testing.expectEqual(@as(u32, 0), lookalike.init_calls);
    try std.testing.expectEqual(@as(u32, 0), lookalike.deinit_calls);
    try std.testing.expectEqual(@as(u32, 0), lookalike.notification_calls);
}

const std = @import("std");

const godot = @import("godot");
