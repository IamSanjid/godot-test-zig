pub fn Notification(
    comptime T: type,
    comptime Base: type,
    comptime auto_onready: bool,
) interface.ClassNotification2 {
    const has_on_ready = comptime auto_onready and findOnReadyFieldNames(T).len > 0;

    if (comptime has_on_ready) {
        // Auto OnReady waits for Node's post-enter-tree notification and probes
        // Node.isNodeReady, so a Node-derived base is a precondition.
        if (comptime !reflect.inheritsFrom(Base, Node)) {
            @compileError("Auto OnReady requires '" ++ @typeName(T) ++ "' to extend a Node, but its base '" ++
                @typeName(Base) ++ "' does not extend " ++ @typeName(Node) ++ ".");
        }

        const base_field_name = comptime findBaseFieldName(T, Base) orelse
            @compileError("Auto OnReady is enabled, but '" ++ @typeName(T) ++
                "' has no field of type `Base(Extends)`. Declare one to use auto OnReady.");

        return &struct {
            fn f(p_instance: interface.ClassInstancePtr, p_what: i32, p_reversed: bool) callconv(.c) void {
                const instance: *T = @ptrCast(@alignCast(p_instance orelse return));

                if (!p_reversed) {
                    if (p_what == Node.notification_post_enter_tree) {
                        const base = &@field(instance, base_field_name);
                        const engine_base = base.get();
                        if (!engine_base.isNodeReady()) {
                            annotations.initOnReadyFields(T, Base, instance, engine_base);
                        }
                    } else if (p_what == Object.notification_extension_reloaded) {
                        // A reload keeps the node in the tree, so post_enter_tree
                        // has already fired; resolve OnReady here instead.
                        const base = &@field(instance, base_field_name);
                        const engine_base = base.get();
                        if (engine_base.isInsideTree()) {
                            annotations.initOnReadyFields(T, Base, instance, engine_base);
                        }
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

const bindings = @import("bindings");
const interface = bindings.interface;

const annotations = @import("../annotations/annotations.zig");
const annot_base = @import("../annotations/base.zig");
const findBaseFieldName = annot_base.findBaseFieldName;
const annot_on_ready = @import("../annotations/on_ready.zig");
const findOnReadyFieldNames = annot_on_ready.findOnReadyFieldNames;
const classes = @import("../classes/classes.zig");
const Node = classes.core.Node;
const Object = classes.core.Object;
const reflect = @import("../reflect/reflect.zig");
