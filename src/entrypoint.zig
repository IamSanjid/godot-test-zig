//! Example extension entry point.
//!
//! Replace `test_zig_init`, the version gate, class-scan imports, and the
//! example registration with your project values. Keep `entry_symbol` in the
//! Godot `.gdextension` file in sync with the exported function name.

pub const std_options: std.Options = .{
    .logFn = godot.richLogFn,
};

export fn test_zig_init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    if (!godot.init(godot.engine_allocator, get_proc_address, library, initialization)) return false;

    var godot_version: gdi.GodotVersion2 = .{};
    godot.dispatch(.get_godot_version2, .{&godot_version});
    if (godot_version.major != 4 or
        godot_version.minor < 7)
    {
        std.log.err("Godot 4.7 or newer is required (found {d}.{d}.{d}).", .{
            godot_version.major, godot_version.minor, godot_version.patch,
        });
        return false;
    }

    godot.registry().addClasses(
        .{example},
        .{
            .auto_onready = true,
            // Editor class: no runtime placeholder in the editor.
            .icon_path = "res://icon.svg",
            .is_runtime = false,
        },
        .{ .instance_allocator = godot.engine_allocator },
    ) catch |err| {
        std.log.err("class registration failed: {t}", .{err});
        return false;
    };

    return true;
}

const std = @import("std");

const godot = @import("godot");
const gdi = godot.bindings.interface;

const example = @import("example.gen.zig");
