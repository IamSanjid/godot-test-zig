// @template method toBinding
pub inline fn toBinding(self: *const {{Builtin}}) bindings.{{binding_builtin}} {
    return @as(*const bindings.{{binding_builtin}}, @ptrCast(self)).*;
}
// @template_end toBinding

// @template method fromBinding
pub inline fn fromBinding(value: bindings.{{binding_builtin}}) {{Builtin}} {
    return @as(*const {{Builtin}}, @ptrCast(&value)).*;
}
// @template_end fromBinding
