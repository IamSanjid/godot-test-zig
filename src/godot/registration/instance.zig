//! Extension-class instance lifecycle callbacks: creation, hot-reload
//! recreation, and freeing.

/// Builds the `create_instance_func` callback for `T`.
pub fn CreateInstance(
    comptime T: type,
    comptime Base: type,
) interface.ClassCreateInstance3 {
    comptime {
        if (!reflect.isEngineObjectClass(Base)) {
            @compileError(std.fmt.comptimePrint(
                "Cannot build the create-instance callback for '{s}': base '{s}' is not an engine object class. " ++
                    "The base must be an instantiable engine class, not a non-instantiable class or an extension class.",
                .{ @typeName(T), @typeName(Base) },
            ));
        }
        if (!@hasDecl(Base, "construct")) {
            @compileError(std.fmt.comptimePrint(
                "Cannot build the create-instance callback for '{s}': base '{s}' has no construct. " ++
                    "The base must be an instantiable engine class, not a non-instantiable class or an extension class.",
                .{ @typeName(T), @typeName(Base) },
            ));
        }
    }
    return &struct {
        fn f(userdata: ?*anyopaque, p_notify_postinitialize: bool) callconv(.c) interface.ObjectPtr {
            const p_registration: *ClassRegistration = @ptrCast(@alignCast(userdata orelse return null));
            const allocator: Allocator = p_registration.instance_allocator;
            const gpa: Allocator = p_registration.gpa orelse allocator;
            const base = Base.construct() orelse return null;

            const child = allocator.create(T) catch {
                ownership.releaseConstructedBase(Base, base);
                return null;
            };

            initializeInstance(T, Base, child, base, gpa) catch |e| {
                std.log.err("Failed to create {s}: {}", .{ @typeName(T), e });
                base.detachInstance(T);
                allocator.destroy(child);
                ownership.releaseConstructedBase(Base, base);
                return null;
            };

            if (p_notify_postinitialize) {
                base.notification(classes.core.Object.notification_postinitialize, .{});
            }
            return base;
        }
    }.f;
}

/// Builds the `recreate_instance_func` callback for `T`, used when the engine
/// hot reloads the extension library. Reuses the create sequence without
/// `Base.construct` and the post-initialize notification, rebuilding the
/// Zig-side instance of an engine object that survived the reload.
pub fn RecreateInstance(
    comptime T: type,
    comptime Base: type,
) interface.ClassRecreateInstance {
    return &struct {
        fn f(userdata: ?*anyopaque, p_object: interface.ObjectPtr) callconv(.c) interface.ClassInstancePtr {
            const p_registration: *ClassRegistration = @ptrCast(@alignCast(userdata orelse return null));
            const allocator: Allocator = p_registration.instance_allocator;
            const gpa: Allocator = p_registration.gpa orelse allocator;
            const base: *Base = @ptrCast(@alignCast(p_object orelse return null));

            const child = allocator.create(T) catch return null;

            initializeInstance(T, Base, child, base, gpa) catch |e| {
                std.log.err("Failed to recreate {s}: {}", .{ @typeName(T), e });
                base.detachInstance(T);
                allocator.destroy(child);
                return null;
            };

            return child;
        }
    }.f;
}

/// Builds the paired `free_instance_func`: DeinitCallback, optional property
/// cleanup, then destroy. A null instance is valid because `detachInstance`
/// clears the engine instance pointer while the extension pointer remains; base
/// destruction then calls this with null.
pub fn FreeInstance(
    comptime T: type,
    comptime Base: type,
    comptime auto_property_cleanup: bool,
) interface.ClassFreeInstance {
    return &struct {
        fn f(userdata: ?*anyopaque, p_instance: interface.ClassInstancePtr) callconv(.c) void {
            const p_registration: *ClassRegistration = @ptrCast(@alignCast(userdata orelse return));
            const instance: *T = @ptrCast(@alignCast(p_instance orelse return));
            annotations.callDeinitCallback(T, Base, instance, p_registration.gpa orelse p_registration.instance_allocator);
            if (comptime auto_property_cleanup) {
                annotations.deinitPropertyFields(T, instance);
            }
            return p_registration.instance_allocator.destroy(instance);
        }
    }.f;
}

/// Runs the creation sequence shared by create and recreate: field defaults,
/// annotation defaults, `Base` marker, attach, `Property` `.init` initializers,
/// then `InitCallback`.
fn initializeInstance(
    comptime T: type,
    comptime Base: type,
    child: *T,
    base: *Base,
    gpa: Allocator,
) !void {
    reflect.initFieldsDefault(T, child);
    annotations.initAnnotFieldsDefault(T, Base, child, base);
    annotations.initBase(T, Base, child, base);
    base.attachInstance(T, child);
    annotations.initPropertyFields(T, Base, child, base);
    try annotations.callInitCallback(T, Base, child, base, gpa);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;

const annotations = @import("../annotations/annotations.zig");
const classes = @import("../classes/classes.zig");
const ownership = @import("../ownership.zig");
const reflect = @import("../reflect/reflect.zig");
const ClassRegistration = @import("ClassRegistration.zig");
