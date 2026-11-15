var _dispatcher: DefaultDispatcher = undefined;
var dispatcher_initialized = false;
var _registry: Registry = undefined;
var registry_initialized = false;

pub fn initializeDispatcher(
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

pub fn initializeRegistry(allocator: std.mem.Allocator) void {
    if (registry_initialized) return;
    _registry = .{ .arena = .init(allocator) };
    registry_initialized = true;
}

pub inline fn dispatcher() *const DefaultDispatcher {
    assert(dispatcher_initialized);
    return &_dispatcher;
}

pub inline fn registery() *Registry {
    assert(registry_initialized);
    return &_registry;
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

pub fn init(
    allocator: std.mem.Allocator,
    get_proc_address: interface.InterfaceGetProcAddress,
    p_library: interface.ClassLibraryPtr,
    initialization: *interface.Initialization,
) bool {
    var diags: DefaultDispatcher.Diagnostics = .{};
    initializeDispatcher(get_proc_address.?, p_library, &diags) catch |e| {
        std.log.err("Initializing dispatch failed, error: {}, {f}", .{ e, diags });
        return false;
    };
    initializeRegistry(allocator);

    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    initialization.* = .{
        .minimum_initialization_level = @fromBackingInt(@intCast(min_init_level)),
        .userdata = null,
        .initialize = &initialize,
        .deinitialize = &deinitialize,
    };

    return true;
}

pub fn richLogFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [if (is_wasm) 256 else 2048]u8 = undefined;
    var bfa = std.heap.BufferFirstAllocator.init(&buffer, engine_allocator);
    var t: std.Io.Writer.Allocating = .init(bfa.allocator());
    defer t.deinit();

    const level_color = comptime switch (level) {
        .err => "red",
        .warn => "yellow",
        .info => "green",
        .debug => "magenta",
    };
    const level_format = comptime "[color=" ++ level_color ++ "][b]" ++ level.asText() ++ "[/b][/color]";
    _ = t.writer.write(level_format) catch return;
    if (scope != .default) _ = t.writer.print("({t})", .{scope}) catch return;
    t.writer.writeAll(": ") catch return;
    // printRich appends \n
    t.writer.print(format, args) catch return;

    var godot_string = builtins.String.fromUtf8(t.written()) catch return;
    defer godot_string.deinit();

    utility.general.printRich(.fromPtr(builtins.String, &godot_string), .{});
}

pub fn initialize(_: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    for (registery().classes.items) |class| {
        if (class.options.register_at_level != p_level) continue;
        dispatch(.classdb_register_extension_class6, .{
            library(),
            &class.class_name,
            &class.parent_class_name,
            &class.creation_info,
        });
    }
}

pub fn deinitialize(_: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    if (@backingInt(p_level) < min_init_level) return;

    while (registery().classes.pop()) |class| {
        if (class.options.register_at_level == p_level) {
            dispatch(.classdb_unregister_extension_class, .{ library(), &class.class_name });
        }
    }
    registery().deinit();
}

const std = @import("std");
const assert = std.debug.assert;
pub const is_wasm = @import("builtin").cpu.arch.isWasm();

const build_options = @import("build_options");

pub const bindings = @import("bindings");
const interface = bindings.interface;
pub const DefaultDispatcher = bindings.Dispatcher(&.{});

pub const naming = @import("naming");

pub const auto = @import("auto/auto.zig");
pub const Registry = @import("Registry.zig");

// Codegen related
pub const builtins = @import("builtins/builtins.zig");
pub const classes = @import("classes/classes.zig");
pub const constants = @import("constants.zig");
pub const enums = @import("enums.zig");
pub const native = @import("native.zig");
pub const singletons = @import("singletons.zig");
pub const utility = @import("utility/utility.zig");

pub const engine_allocator = @import("heap.zig").engine_allocator;
