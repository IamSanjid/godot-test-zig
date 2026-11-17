// @templates_for Object:derived

// @section artifact typeToken

pub fn typeToken(comptime T: type) ?*anyopaque {
    const token = &struct {
        pub var _token: u8 = 34 + 35;
        pub const TT = T;
    }._token;
    return token;
}

// @section_end artifact typeToken

// @section artifact setInstance

/// Bind an instance of an extension class to this engine class.
pub fn setInstance(self: *{{Class}}, comptime T: type, instance: *T) void {
    comptime if (!runtime.reflect.inheritsFrom(T, {{Class}})) {
        @compileError("T must extend {{Class}} or any of its derived classes, by declaring an `Extends` alias to the base class.");
    };

    const token = comptime typeToken(T);
    const class_name: builtins.StringName = .fromComptimeLatin1(runtime.reflect.className(T));
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

// @section_end artifact setInstance

// @section artifact asInstance

/// Returns the registered instance of extension class T, or null if no binding exists.
pub fn asInstance(self: *{{Class}}, comptime T: type) ?*T {
    comptime std.debug.assert(runtime.reflect.inheritsFrom(T, {{Class}}));
    comptime std.debug.assert(runtime.reflect.isNormalStruct(T));

    const token = comptime typeToken(T);
    const instance = runtime.dispatch(.object_get_instance_binding, .{self, token, null}) orelse return null;
    return @ptrCast(@alignCast(instance));
}

// @section_end artifact asInstance

// @section artifact upcast

pub inline fn upcast(self: *{{Class}}, comptime T: type) *T {
    if (!comptime runtime.reflect.inheritsFrom({{Class}}, T)) @compileError("{{Class}} doesn't extend, " ++ @typeName(T));
    return @ptrCast(self);
}
// @section_end artifact upcast

// @section artifact downcast

pub inline fn downcast(self: *{{Class}}, comptime T: type) ?*T {
    return if (self.isClass(builtins.StringName.fromComptimeLatin1(runtime.reflect.className(T)))) @ptrCast(self) else null;
}

// @section_end artifact downcast
