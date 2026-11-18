// @section artifact destroy
/// Immediately destroys the object. Prefer `queueFree` in most situations. It's supposed to be a "static" method.
pub fn destroy(dispatcher: anytype, self: *@This()) void {
    dispatcher.dispatch(.object_destroy, .{@ptrCast(self)});
}
// @section_end artifact destroy

// @section replace getInstanceId
/// Returns the instance id directly through the GDExtension interface.
pub fn getInstanceId(self: *const Object, dispatcher: anytype) u64 {
    return dispatcher.dispatch(.object_get_instance_id, .{@as(interface.ConstObjectPtr, @ptrCast(self))});
}
// @section_end replace getInstanceId
