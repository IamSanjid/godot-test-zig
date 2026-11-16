// @templates_for *

// @section artifact toBinding
pub inline fn toBinding(self: *const {{Builtin}}) bindings.{{binding_builtin}} {
    return @as(*const bindings.{{binding_builtin}}, @ptrCast(self)).*;
}
// @section_end artifact toBinding

// @section artifact fromBinding
pub inline fn fromBinding(value: bindings.{{binding_builtin}}) {{Builtin}} {
    return @as(*const {{Builtin}}, @ptrCast(&value)).*;
}
// @section_end artifact fromBinding
