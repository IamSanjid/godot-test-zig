/// This is used to create instance of the type, it's useful when you want it to be part of some pool.
/// Will be passed to init callbacks/and other "annot" callbacks if `gpa` is null.
/// Must be valid for every possible interactions with the type instance.
create_allocator: Allocator,
/// If set, it will be passed to init callbacks/and other "annot" callbacks eg. OnReady, Init...
/// Must be valid for every possible interactions with the type instance.
gpa: ?Allocator = null,
register_at_level: interface.InitializationLevel = .scene,

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;
