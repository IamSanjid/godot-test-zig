var _dispatcher: DefaultDispatcher = undefined;
var dispatcher_initialized = false;
pub fn initialize_dispatcher(
    getProcAddress: std.meta.Child(interface.InterfaceGetProcAddress),
    p_library: interface.ClassLibraryPtr,
    diags: ?*DefaultDispatcher.Diagnostics,
) !void {
    if (dispatcher_initialized) {
        return;
    }
    _dispatcher = try .init(getProcAddress, p_library, diags);
    dispatcher_initialized = true;
}

pub inline fn dispatcher() *const DefaultDispatcher {
    assert(dispatcher_initialized);
    return &_dispatcher;
}

pub inline fn dispatch(
    comptime proc: interface.ProcsTag,
    args: DefaultDispatcher.ProcArgumentTypesAsTuple(proc),
) DefaultDispatcher.ProcReturnAddress(proc) {
    return dispatcher().dispatch(proc, args);
}

pub inline fn library() interface.ClassLibraryPtr {
    return dispatcher().library;
}

pub fn defaultInit(
    get_proc_address: interface.InterfaceGetProcAddress,
    p_library: interface.ClassLibraryPtr,
    initialization: *interface.Initialization,
) bool {
    var diags: DefaultDispatcher.Diagnostics = .{};
    initialize_dispatcher(get_proc_address.?, p_library, &diags) catch |e| {
        std.log.err("Initializing dispatch failed, error: {}, {f}", .{ e, diags });
        return false;
    };

    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    initialization.* = .{
        .minimum_initialization_level = @fromBackingInt(@intCast(min_init_level)),
        .userdata = null,
        .initialize = &scannedClassesInitialize,
        .deinitialize = &scannedClassesDeinitialize,
    };

    return true;
}

pub fn scannedClassesInitialize(p_userdata: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    _ = p_userdata;
    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    if (@backingInt(p_level) < min_init_level) return;
}

pub fn scannedClassesDeinitialize(p_userdata: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    _ = p_userdata;
    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    if (@backingInt(p_level) < min_init_level) return;
}

const std = @import("std");
const assert = std.debug.assert;

const build_options = @import("build_options");
pub const bindings = @import("bindings/bindings.zig");
const interface = bindings.interface;
pub const DefaultDispatcher = bindings.Dispatcher(&.{});
pub const engine_allocator = @import("heap.zig").engine_allocator;
