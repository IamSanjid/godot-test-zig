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

const TestNode = struct {
    pub const Extends = classes.core.Node;

    pub fn _ready(_: *const @This()) void {
        const value: u8 = 69;
        const fmt = builtins.StringName.fromComptimeLatin1("[color=green]**Value**[/color]: %d %v %v %v");
        var array: builtins.Array = .init();
        defer array.deinit();
        array.append(.fromPtr(u8, &value));
        const vector: builtins.Vector2 = .{ .x = 69, .y = 420 };
        const direction_to = vector.bindingCallConst(.directionTo, .{builtins.Vector2{ .x = 69, .y = 410 }});
        const direction_to2 = vector.directionTo(builtins.Vector2{ .x = 69, .y = 430 });
        array.append(.fromPtr(builtins.Vector2, @as(*const builtins.Vector2, @ptrCast(&vector))));
        array.append(.fromPtr(builtins.Vector2, @as(*const builtins.Vector2, @ptrCast(&direction_to))));
        array.append(.fromPtr(builtins.Vector2, @as(*const builtins.Vector2, @ptrCast(&direction_to2))));

        const value_from_array0 = array.indexConst(0).asInt();
        std.log.debug("value_from_array0: {}", .{value_from_array0});

        const fmt1 = fmt.opModArray(&array);
        utility.general.printRich(
            .fromPtr(builtins.String, &fmt1),
            .{},
        );
        std.log.debug("The _ready was called! vector: {}", .{vector.toBinding()});
    }
};
pub fn scannedClassesInitialize(p_userdata: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    _ = p_userdata;
    if (p_level == .scene) {
        const class_name: builtins.StringName = .fromType(TestNode);
        const parent_class_name: builtins.StringName = .fromType(TestNode.Extends);
        const class_info: interface.ClassCreationInfo6 = .{
            .is_exposed = true,
            .create_instance_func = &struct {
                fn f(_: ?*anyopaque, p_notify_postinitialize: bool) callconv(.c) interface.ObjectPtr {
                    const base = TestNode.Extends.construct() orelse return null;
                    const self = engine_allocator.create(TestNode) catch return null;
                    base.setInstance(TestNode, self);
                    std.log.debug("created TestNode!", .{});
                    if (p_notify_postinitialize) {
                        base.notification(TestNode.Extends.notification_postinitialize, .{});
                    }
                    return base;
                }
            }.f,
            .free_instance_func = &struct {
                fn f(_: ?*anyopaque, p_instance: interface.ClassInstancePtr) callconv(.c) void {
                    const self: *TestNode = @ptrCast(p_instance);
                    return engine_allocator.destroy(self);
                }
            }.f,
            .get_virtual_func = &struct {
                fn f(_: ?*anyopaque, p_name: interface.ConstStringNamePtr, p_hash: u32) callconv(.c) interface.ClassCallVirtual {
                    @setRuntimeSafety(false);
                    const p_method_name: *const builtins.StringName = @ptrCast(@alignCast(p_name orelse return null));
                    const ready_method_name: builtins.StringName = .fromComptimeLatin1("_ready");
                    if (!ready_method_name.opEqlStringName(p_method_name)) return null;
                    if (p_hash != 3218959716) return null;
                    std.log.debug("was looking for ready!!", .{});
                    return &struct {
                        fn f(p_instance: interface.ClassInstancePtr, _: [*c]const interface.ConstTypePtr, _: interface.TypePtr) callconv(.c) void {
                            const self: *TestNode = @ptrCast(p_instance);
                            self._ready();
                        }
                    }.f;
                }
            }.f,
        };
        dispatch(.classdb_register_extension_class6, .{
            library(),
            &class_name,
            &parent_class_name,
            &class_info,
        });
    }
}

var unreg = false;
pub fn scannedClassesDeinitialize(p_userdata: ?*anyopaque, p_level: interface.InitializationLevel) callconv(.c) void {
    _ = p_userdata;
    const min_init_level = @backingInt(build_options.minimum_initialization_level);
    if (@backingInt(p_level) < min_init_level) return;

    if (unreg) return;
    unreg = true;
    const class_name: builtins.StringName = .fromType(TestNode);
    dispatch(.classdb_unregister_extension_class, .{ library(), &class_name });
}

const std = @import("std");
const assert = std.debug.assert;

const build_options = @import("build_options");

pub const bindings = @import("bindings");
const interface = bindings.interface;
pub const DefaultDispatcher = bindings.Dispatcher(&.{});

pub const auto = @import("auto/auto.zig");
pub const builtins = @import("builtins/builtins.zig");
pub const classes = @import("classes/classes.zig");
pub const constants = @import("constants.zig");
pub const enums = @import("enums.zig");
pub const native = @import("native.zig");
pub const singletons = @import("singletons.zig");
pub const utility = @import("utility/utility.zig");

pub const engine_allocator = @import("heap.zig").engine_allocator;
