comptime {
    @export(&init, .{
        .name = build_options.entry_point,
        .linkage = .strong,
    });
}

fn init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    var diags: gdi.Procs.Diagnostics = .{};
    godot.initialize_dispatch(get_proc_address.?, library, &diags) catch |e| {
        std.log.err("Initializing dispatch failed, error: {}, {f}", .{ e, diags });
        return false;
    };

    var godot_version: gdi.GodotVersion2 = .{};
    godot.dispatch.procs.getGodotVersion2(&godot_version);
    if (godot_version.major != 4 or
        godot_version.minor < 7)
    {
        std.log.err("Unsupported godot, required at least 4.7", .{});
        return false;
    }

    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    initialization.* = .{
        .minimum_initialization_level = @fromBackingInt(@intCast(min_init_level)),
        .userdata = null,
        .initialize = null,
        .deinitialize = null,
    };

    return true;
}

const build_options = @import("build_options");
const std = @import("std");
const godot = @import("godot/godot.zig");
const gdi = godot.interface;
