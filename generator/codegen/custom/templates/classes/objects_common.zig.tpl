// @templates_for Object:derived

// @template method setInstance

/// Bind an instance of an extension class to this engine class.
pub fn setInstance(self: *{{Class}}, comptime T: type, instance: *T) void {
    comptime if (!runtime.auto.inheritsFrom(T, {{Class}})) {
        @compileError("T must extend {{Class}} or any of its derived classes, by declaring an `Extends` alias to the base class.");
    };

    const token = comptime &struct {
        pub var _token: u8 = 34 + 35;
        pub const TT = T;
    }._token;
    const class_name: builtins.StringName = .fromType(T);
    runtime.dispatch(.object_set_instance, .{ self, &class_name, instance });
    runtime.dispatch(.object_set_instance_binding, .{ self, token, instance, &struct {
        const callbacks: bindings.interface.InstanceBindingCallbacks = .{
            .create_callback = noop_create_callback,
            .free_callback = noop_free_callback,
            .reference_callback = noop_reference_callback,
        };

        fn noop_create_callback(_: ?*anyopaque, _: ?*anyopaque) callconv(.c) ?*anyopaque {
            return null;
        }

        fn noop_free_callback(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {}

        fn noop_reference_callback(_: ?*anyopaque, _: ?*anyopaque, _: bool) callconv(.c) bool {
            return true;
        }
    }.callbacks });
}
// @template_end setInstance
