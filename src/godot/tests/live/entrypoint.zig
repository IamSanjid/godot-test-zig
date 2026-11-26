//! Live test extension entry point.
//!
//! `godot-test/test_extension.gdextension` loads this library as
//! `test_extension_init`; `godot-test/run_tests.gd` then reads the registered
//! class metadata back through the engine ClassDB API. This file only exports
//! the entry symbol and registers fixture classes; class declarations live in
//! sibling `.zig` files.

export fn test_extension_init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    if (!godot.init(godot.engine_allocator, get_proc_address, library, initialization)) {
        std.log.err("live test extension: godot.init failed", .{});
        return false;
    }

    godot.registry().addClasses(
        .{
            live_node.LiveNode,
            live_owned_node.LiveOwnedNode,
            live_resource.LiveResource,
            live_typed_node.LiveTypedNode,
        },
        .{},
        .{ .instance_allocator = godot.engine_allocator },
    ) catch |err| {
        std.log.err("live test extension: class registration failed: {t}", .{err});
        return false;
    };

    return true;
}

const std = @import("std");

const godot = @import("godot");
const gdi = godot.bindings.interface;

const live_node = @import("live_node.zig");
const live_owned_node = @import("live_owned_node.zig");
const live_resource = @import("live_resource.zig");
const live_typed_node = @import("live_typed_node.zig");
