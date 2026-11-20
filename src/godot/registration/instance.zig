//! Extension-class instance lifecycle callbacks.

/// Builds the `create_instance_func` callback for `T`.
pub const CreateInstance = @import("create_instance.zig").CreateInstance;

/// Builds the paired `free_instance_func`: DeinitCallback, optional property
/// cleanup, then destroy.
pub fn FreeInstance(
    comptime T: type,
    comptime Base: type,
    comptime auto_property_cleanup: bool,
) interface.ClassFreeInstance {
    return &struct {
        fn f(userdata: ?*anyopaque, p_instance: interface.ClassInstancePtr) callconv(.c) void {
            const p_registration: *ClassRegistration = @ptrCast(@alignCast(userdata orelse return));
            const instance: *T = @ptrCast(@alignCast(p_instance));
            annotations.callDeinitCallback(T, Base, instance, p_registration.gpa orelse p_registration.create_allocator);
            if (comptime auto_property_cleanup) {
                annotations.deinitPropertyFields(T, instance);
            }
            return p_registration.create_allocator.destroy(instance);
        }
    }.f;
}

const bindings = @import("bindings");
const interface = bindings.interface;

const ClassRegistration = @import("ClassRegistration.zig");

const annotations = @import("../annotations/annotations.zig");
