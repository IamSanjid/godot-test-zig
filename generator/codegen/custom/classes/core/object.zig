// @method destroy
/// Immediately destroys the object. Prefer `queueFree` in most situations. It's supposed to be a "static" method.
pub fn destroy(self: *@This()) void {
    runtime.dispatch(.object_destroy, .{@ptrCast(self)});
}
// @method_end destroy
