//! Opt-in markers: field wrappers (Base, OnReady, Property), callback and
//! override markers, class-level `Signal`/`Constants`/`PropertyGroups`
//! metadata, the `Conversion` value-type marker, and the `Init` initializer.

const base = @import("base.zig");
pub const Base = base.Base;
pub const initBase = base.initBase;

const init_callback = @import("init_callback.zig");
pub const InitCallback = init_callback.InitCallback;
pub const callInitCallback = init_callback.callInitCallback;

const deinit_callback = @import("deinit_callback.zig");
pub const DeinitCallback = deinit_callback.DeinitCallback;
pub const callDeinitCallback = deinit_callback.callDeinitCallback;

const init = @import("init.zig");
/// Wraps a function and comptime argument tuple for deferred invocation; used
/// by `OnReady(...).Call` (resolved by `initOnReadyFields`) and the `Property`
/// `.init` option (run at creation).
pub const Init = init.Init;

const on_ready = @import("on_ready.zig");
pub const OnReady = on_ready.OnReady;
pub const initOnReadyFields = on_ready.initOnReadyFields;
pub const findOnReadyFieldNames = on_ready.findOnReadyFieldNames;

const notification_callback = @import("notification_callback.zig");
pub const NotificationCallback = notification_callback.NotificationCallback;
pub const callNotificationCallback = notification_callback.callNotificationCallback;

const signal = @import("signal.zig");
pub const Signal = signal.Signal;
pub const findSignals = signal.findSignals;

/// `Constants` marker and discovery helpers.
pub const constants = @import("constants.zig");
pub const Constants = constants.Constants;
pub const ConstantEntry = constants.Entry;
pub const findConstants = constants.findConstants;

const override = @import("override.zig");
pub const Override = override.Override;

/// `Conversion` marker for custom value-type conversion; `conversion.zig`
/// validates its functions against the owner type.
const conversion = @import("conversion.zig");
pub const Conversion = conversion.Conversion;

/// `Property`/`PropertyGroups` markers, field initialization/cleanup, and the
/// property-introspection helpers used by registration and tests.
pub const property = @import("property.zig");
pub const Property = property.Property;
pub const PropertyGroups = property.PropertyGroups;
pub const initPropertyFields = property.initPropertyFields;
pub const deinitPropertyFields = property.deinitPropertyFields;

/// Shared annotation marker identity (`Kind`, `kindOf`, and `is`). Registration
/// and discovery use it to tell annotation types apart.
pub const marker = @import("marker.zig");

pub fn initAnnotFieldsDefault(comptime T: type, comptime B: type, child: *T, b: *B) void {
    _ = b;
    inline for (comptime on_ready.findOnReadyFieldNames(T)) |field| {
        @field(child, field) = .{};
    }
}

/// Wraps a comptime-argument function so it can be used as a normal runtime
/// dispatchable function, e.g. for `.call` strategies that need comptime args.
pub fn callComptimeArg1(comptime f: anytype, comptime arg: anytype) fn () (reflect.FnReturnType(f) orelse void) {
    return struct {
        fn wrapper() (reflect.FnReturnType(f) orelse void) {
            return f(arg);
        }
    }.wrapper;
}

const reflect = @import("../reflect/reflect.zig");
