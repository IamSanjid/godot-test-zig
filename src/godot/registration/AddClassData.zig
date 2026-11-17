/// Runtime data stored once per `addClasses` call and shared by all classes in
/// that group. The heap-allocated copy is passed to the engine as
/// `class_userdata`, so it must stay valid for every interaction with the
/// class's instances.
create_allocator: Allocator,
/// If set, it will be passed to init callbacks and other annotation callbacks
/// eg. OnReady, Init. Must be valid for every possible interaction with the
/// type instance.
gpa: ?Allocator = null,
register_at_level: interface.InitializationLevel = .scene,

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;
