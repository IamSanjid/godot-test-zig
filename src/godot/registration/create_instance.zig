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
            const p_options: *AddClassData = @ptrCast(@alignCast(userdata orelse return null));
            const allocator: Allocator = p_options.create_allocator;
            const gpa: Allocator = p_options.gpa orelse allocator;
            const base = Base.construct() orelse return null;

            const child = allocator.create(T) catch {
                destroyBase(Base, base);
                return null;
            };
            reflect.initFieldsDefault(T, child);
            annotations.initAnnotFieldsDefault(T, Base, child, base);
            annotations.initBase(T, Base, child, base);
            annotations.callInitCallback(T, Base, child, base, gpa) catch |e| {
                std.log.err("Failed to create {s}: {}", .{ @typeName(T), e });
                allocator.destroy(child);
                destroyBase(Base, base);
                return null;
            };

            base.setInstance(T, child);
            if (p_notify_postinitialize) {
                base.notification(classes.core.Object.notification_postinitialize, .{});
            }
            return base;
        }
    }.f;
}

/// Release a constructed base on a failed extension instance creation.
/// A RefCounted base owns one reference from `classdb_construct_object3`;
/// release that reference instead of bypassing the refcount with object_destroy.
fn destroyBase(comptime Base: type, base: *Base) void {
    if (comptime reflect.isRefCounted(Base) and @hasDecl(Base, "unreference")) {
        _ = base.unreference();
        return;
    }
    runtime.dispatch(.object_destroy, .{base});
}
const std = @import("std");
const Allocator = std.mem.Allocator;

const AddClassData = @import("AddClassData.zig");

const bindings = @import("bindings");
const interface = bindings.interface;
const classes = @import("../classes/classes.zig");

const runtime = @import("../runtime.zig");
const reflect = @import("../reflect/reflect.zig");
const annotations = @import("../annotations/annotations.zig");
