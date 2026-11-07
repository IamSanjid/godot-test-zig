library: wrapper.ClassLibraryPtr,
procs: wrapper.Procs,

pub fn init(
    getProcAddress: Child(wrapper.InterfaceGetProcAddress),
    library: wrapper.ClassLibraryPtr,
    diags: ?*wrapper.Procs.Diagnostics,
) !Dispatch {
    return .{
        .library = library,
        .procs = try .init(getProcAddress, diags),
    };
}

const Dispatch = @This();

const std = @import("std");
const Child = std.meta.Child;

const wrapper = @import("bindings/interface_wrapper.zig");
