// @section artifact destroy
/// Immediately destroys the object. Prefer `queueFree` in most situations. It's supposed to be a "static" method.
pub fn destroy(self: *@This()) void {
    runtime.dispatch(.object_destroy, .{@ptrCast(self)});
}
// @section_end artifact destroy

// @section replace getInstanceId
/// Returns the instance id directly through the GDExtension interface.
pub inline fn getInstanceId(self: *const Object) u64 {
    return runtime.dispatch(.object_get_instance_id, .{@as(bindings.interface.ConstObjectPtr, @ptrCast(self))});
}
// @section_end replace getInstanceId
