//! Extension-class instance lifecycle callbacks.
//!
//! These are standalone builders: `Registry` passes them to
//! `classdb_register_extension_class6`, and a user with a different registration
//! model can reuse them directly. They only depend on `AddClassData`, not on
//! `Registry` state.

/// Builds the `create_instance_func` callback for `T`.
pub const CreateInstance = @import("create_instance.zig").CreateInstance;

/// Builds the `free_instance_func` callback paired with `CreateInstance`.
///
/// `userdata` is the `*AddClassData` stored as `class_userdata`. The optional
/// `DeinitCallback` runs first, then the instance is destroyed with
/// `AddClassData.create_allocator`.
pub fn FreeInstance(
    comptime T: type,
    comptime Base: type,
) interface.ClassFreeInstance {
    return &struct {
        fn f(userdata: ?*anyopaque, p_instance: interface.ClassInstancePtr) callconv(.c) void {
            const p_data: *AddClassData = @ptrCast(@alignCast(userdata orelse return));
            const instance: *T = @ptrCast(@alignCast(p_instance));
            annotations.callDeinitCallback(T, Base, instance, p_data.gpa orelse p_data.create_allocator);
            return p_data.create_allocator.destroy(instance);
        }
    }.f;
}

const bindings = @import("bindings");
const interface = bindings.interface;

const AddClassData = @import("AddClassData.zig");

const annotations = @import("../annotations/annotations.zig");
