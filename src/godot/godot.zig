pub var dispatch: @import("Dispatch.zig") = undefined;
pub fn initialize_dispatch(
    getProcAddress: std.meta.Child(interface.InterfaceGetProcAddress),
    library: interface.ClassLibraryPtr,
    diags: ?*interface.Procs.Diagnostics,
) !void {
    dispatch = try .init(getProcAddress, library, diags);
}

const std = @import("std");
pub const interface = @import("bindings/interface_wrapper.zig");
