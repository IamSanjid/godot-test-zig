// @struct Object
/// Immediately destroys the object. Prefer `queueFree` in most situations. It's supposed to be a "static" method.
pub fn destroy(dispatcher: anytype, self: *@This()) void {
    dispatcher.dispatch(.object_destroy, .{@ptrCast(self)});
}
// @struct_end Object
