pub fn Notification(
    comptime T: type,
    comptime Base: type,
    comptime auto_onready: bool,
) interface.ClassNotification2 {
    const has_on_ready = comptime auto_onready and findOnReadyFieldNames(T).len > 0;

    if (comptime has_on_ready) {
        const base_field_name = comptime findBaseFieldName(T, Base) orelse
            @compileError("Auto OnReady is enabled, but '" ++ @typeName(T) ++
                "' has no field of type `Base(Extends)`. Declare one to use auto OnReady.");

        return &struct {
            fn f(p_instance: interface.ClassInstancePtr, p_what: i32, p_reversed: bool) callconv(.c) void {
                const instance: *T = @ptrCast(@alignCast(p_instance orelse return));

                if (p_what == Node.notification_post_enter_tree and !p_reversed) {
                    const base = &@field(instance, base_field_name);
                    if (!base.get().isNodeReady()) {
                        annotations.initOnReadyFields(T, Base, instance, base.get());
                    }
                }

                annotations.callNotificationCallback(T, Base, instance, p_what, p_reversed);
            }
        }.f;
    } else {
        return &struct {
            fn f(p_instance: interface.ClassInstancePtr, p_what: i32, p_reversed: bool) callconv(.c) void {
                const instance: *T = @ptrCast(@alignCast(p_instance orelse return));
                annotations.callNotificationCallback(T, Base, instance, p_what, p_reversed);
            }
        }.f;
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;
const classes = @import("../classes/classes.zig");
const Node = classes.core.Node;

const annotations = @import("../annotations/annotations.zig");

const annot_base = @import("../annotations/base.zig");
const findBaseFieldName = annot_base.findBaseFieldName;

const annot_on_ready = @import("../annotations/on_ready.zig");
const findOnReadyFieldNames = annot_on_ready.findOnReadyFieldNames;
