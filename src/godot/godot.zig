//! Public facade for the Zig GDExtension runtime.
//!
//! Process-wide state, the dispatcher, the registry, and the engine lifecycle
//! live in `runtime.zig`. Generated dispatch code imports `runtime.zig` directly;
//! user code imports this facade as `godot`.
//!
//! `godot.richLogFn` is kept here so `std_options.logFn` can reference it
//! without importing `runtime.zig` directly.

/// Process-wide runtime state. Generated code imports this directly; user code
/// can reach it as `godot.runtime`.
pub const runtime = @import("runtime.zig");
pub const initializeDispatcher = runtime.initializeDispatcher;
pub const initializeRegistry = runtime.initializeRegistry;
pub const dispatcher = runtime.dispatcher;
pub const registry = runtime.registry;
pub const dispatch = runtime.dispatch;
pub const library = runtime.library;
pub const init = runtime.init;
pub const richLogFn = runtime.richLogFn;
pub const initialize = runtime.initialize;
pub const deinitialize = runtime.deinitialize;
pub const DefaultDispatcher = runtime.DefaultDispatcher;
pub const is_wasm = runtime.is_wasm;
pub const engine_allocator = runtime.engine_allocator;
pub const reflect = runtime.reflect;

pub const bindings = @import("bindings");

pub const naming = @import("naming");

pub const annotations = @import("annotations/annotations.zig");

pub const ownership = @import("ownership.zig");

pub const abi = @import("abi.zig");

pub const registration = @import("registration/registration.zig");
pub const Registry = registration.Registry;

// Codegen related
pub const builtins = @import("builtins/builtins.zig");

pub const classes = @import("classes/classes.zig");

pub const constants = @import("constants.zig");

pub const enums = @import("enums.zig");

pub const native = @import("native.zig");

pub const singletons = @import("singletons.zig");

pub const utility = @import("utility/utility.zig");
