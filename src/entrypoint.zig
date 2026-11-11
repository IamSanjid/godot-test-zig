export fn test_zig_init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    if (!godot.defaultInit(get_proc_address, library, initialization)) return false;

    const value = godot.engine_allocator.create(u8) catch return false;
    value.* = 69;
    defer godot.engine_allocator.destroy(value);

    var godot_version: gdi.GodotVersion2 = .{};
    godot.dispatch(.get_godot_version2, .{&godot_version});
    if (godot_version.major != 4 or
        godot_version.minor < 7)
    {
        std.log.err("Need at least 4.7 godot.", .{});
        return false;
    } else {
        std.log.debug("Value allocated: {*} with: {}", .{ value, value.* });
    }

    return true;
}

const std = @import("std");

const godot = @import("godot");
const gdi = godot.bindings.interface;
