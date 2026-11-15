pub fn CreateInstance(
    comptime T: type,
    comptime Base: type,
) interface.ClassCreateInstance3 {
    return &struct {
        fn f(userdata: ?*anyopaque, p_notify_postinitialize: bool) callconv(.c) interface.ObjectPtr {
            const p_options: *AddClassData = @ptrCast(@alignCast(userdata orelse return null));
            const allocator: Allocator = p_options.create_allocator;
            const gpa: Allocator = if (p_options.gpa != null) p_options.gpa.? else allocator;
            const base = Base.construct() orelse return null;

            const child = allocator.create(T) catch {
                runtime.dispatch(.object_destroy, .{base});
                return null;
            };
            auto.initFieldsDefault(T, child);
            auto.annot.initAnnotFieldsDefault(T, Base, child, base);
            auto.annot.initBase(T, Base, child, base);
            auto.annot.callInitCallback(T, Base, child, base, gpa) catch |e| {
                std.log.err("Failed to create {s}: {}", .{ @typeName(T), e });
                allocator.destroy(child);
                runtime.dispatch(.object_destroy, .{base});
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

const std = @import("std");
const Allocator = std.mem.Allocator;

const AddClassData = @import("AddClassData.zig");

const bindings = @import("bindings");
const interface = bindings.interface;
const classes = @import("../classes/classes.zig");

const runtime = @import("../godot.zig");
const auto = runtime.auto;
