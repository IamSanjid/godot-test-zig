const build_options = @import("build_options");
const gdi = @import("godot_interface");

comptime {
    @export(&init, .{
        .name = build_options.entry_point,
        .linkage = .strong,
    });
}

fn init(
    get_proc_address: gdi.GDExtensionInterfaceGetProcAddress,
    library: gdi.GDExtensionClassLibraryPtr,
    initialization: *gdi.GDExtensionInitialization,
) callconv(.c) bool {
    _ = get_proc_address;
    _ = library;

    initialization.* = .{
        .minimum_initialization_level = @backingInt(build_options.minimum_initialization_level),
        .userdata = null,
        .initialize = null,
        .deinitialize = null,
    };

    return false;
}
