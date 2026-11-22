//! Opt-in markers: field annotations (Base, OnReady, Property, callbacks),
//! class-level `Signal`/`Constants` metadata, and the `Init` shared initializer.

pub const Base = base.Base;
pub const initBase = base.initBase;

pub const InitCallback = init_callback.InitCallback;
pub const callInitCallback = init_callback.callInitCallback;

pub const DeinitCallback = deinit_callback.DeinitCallback;
pub const callDeinitCallback = deinit_callback.callDeinitCallback;

/// Wraps a function and comptime argument tuple for deferred creation-time
/// invocation; used by `OnReady(...).Call` and the `Property` `.init` option.
pub const Init = init.Init;

pub const OnReady = on_ready.OnReady;
pub const initOnReadyFields = on_ready.initOnReadyFields;
pub const findOnReadyFieldNames = on_ready.findOnReadyFieldNames;

pub const NotificationCallback = notification_callback.NotificationCallback;
pub const callNotificationCallback = notification_callback.callNotificationCallback;

pub const Signal = signal.Signal;
pub const findSignals = signal.findSignals;

pub const Constants = constants.Constants;
pub const ConstantEntry = constants.Entry;
pub const findConstants = constants.findConstants;

pub const Override = override.Override;

pub const Property = property.Property;
pub const PropertyDescriptor = property.PropertyDescriptor;
pub const findPropertyFieldNames = property.findPropertyFieldNames;
pub const descriptors = property.descriptors;
pub const isPropertyField = property.isPropertyField;
pub const PropertyValueType = property.PropertyValueType;
pub const hasCustomGetter = property.hasCustomGetter;
pub const hasCustomSetter = property.hasCustomSetter;
pub const getterFn = property.getterFn;
pub const setterFn = property.setterFn;
pub const isWritable = property.isWritable;
pub const isReadOnly = property.isReadOnly;
pub const hasCustomInitializer = property.hasCustomInitializer;
pub const initPropertyFields = property.initPropertyFields;
pub const hasCustomDeinit = property.hasCustomDeinit;
pub const deinitFn = property.deinitFn;
pub const deinitPropertyFields = property.deinitPropertyFields;
pub const isKnownManagedBuiltin = property.isKnownManagedBuiltin;
pub const retainRefCounted = property.retainRefCounted;
pub const releaseRefCounted = property.releaseRefCounted;

/// Shared annotation marker identity (`Kind`, `kindOf`, and `is`). Registration
/// and discovery use it to tell annotation wrappers apart.
pub const marker = @import("marker.zig");

pub fn initAnnotFieldsDefault(comptime T: type, comptime B: type, child: *T, b: *B) void {
    _ = b;
    inline for (comptime on_ready.findOnReadyFieldNames(T)) |field| {
        @field(child, field) = .{};
    }
}

// Keep the compile-only Property discovery checks analyzed on a plain build,
// even when no registered class declares a Property field.
comptime {
    property.comptimeSelfCheck();
}

// Compile-only integration coverage: annotation field initialization must only
// touch OnReady fields, even when a class also declares Property fields.
const MixedFieldOwner = struct {
    node: OnReady(classes.core.Node).Node("./ChildNode"),
    health: Property(i32, .{ .usage = .exported }) = .init(0),
};

fn checkMixedFieldOwner() void {
    if (comptime findOnReadyFieldNames(MixedFieldOwner).len != 1)
        @compileError("initAnnotFieldsDefault must not treat Property fields as OnReady fields");
    var owner: MixedFieldOwner = .{ .node = .{} };
    var dummy_base: void = {};
    initAnnotFieldsDefault(MixedFieldOwner, void, &owner, &dummy_base);
    if (owner.node.value != null) @compileError("initAnnotFieldsDefault must initialize OnReady fields");
    if (owner.health.value != 0) @compileError("initAnnotFieldsDefault must not touch Property fields");
}

comptime {
    checkMixedFieldOwner();
}

// Compile-only integration coverage: the exported `.read_only` / `.init` API
// composes through the annotations facade, including eager initializer
// assignment and read-only dispatch policy.
fn five() u32 {
    return 5;
}

const PropertyApiOwner = struct {
    sealed: Property(u32, .{ .usage = .none, .read_only = true }) = .init(1),
    seeded: Property(u32, .{
        .usage = .none,
        .init = Init(u32, five, .{}),
    }) = .init(0),
};

fn checkPropertyApiOwner() void {
    var owner: PropertyApiOwner = .{};
    var dummy_base: void = {};
    initPropertyFields(PropertyApiOwner, void, &owner, &dummy_base);
    if (owner.seeded.value != 5) @compileError("annotations.initPropertyFields must assign .init results eagerly");
    if (owner.sealed.value != 1) @compileError("annotations.initPropertyFields must not touch fields without .init");
    if (!isReadOnly(PropertyApiOwner, "sealed")) @compileError(".read_only properties must be read-only");
    if (isWritable(PropertyApiOwner, "sealed")) @compileError(".read_only properties must not be writable");
    if (getterFn(PropertyApiOwner, "sealed")(&owner) != 1) @compileError(".read_only properties must keep the default getter");
    if (!hasCustomInitializer(@FieldType(PropertyApiOwner, "seeded"))) @compileError("annotations.hasCustomInitializer must detect .init");
}

comptime {
    checkPropertyApiOwner();
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

const base = @import("base.zig");
const init = @import("init.zig");
const init_callback = @import("init_callback.zig");
const deinit_callback = @import("deinit_callback.zig");
const on_ready = @import("on_ready.zig");
const notification_callback = @import("notification_callback.zig");
const override = @import("override.zig");
const property = @import("property.zig");
const constants = @import("constants.zig");
const signal = @import("signal.zig");

const reflect = @import("../reflect/reflect.zig");
const classes = @import("../classes/classes.zig");
