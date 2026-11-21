instance_allocator: Allocator,
gpa: ?Allocator = null,
register_at_level: interface.InitializationLevel = .scene,

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;
