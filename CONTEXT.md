# Project context

This repository is a template Godot GDExtension project written in Zig. It
combines generated GDExtension bindings and dispatch wrappers with a small
hand-written runtime layer.

The template is intentionally a starting point, not a framework. Generated code
and hand-written policy stay separate, annotations are opt-in, `Registry` is an
optional convenience collector, and no allocation, pooling, or instance-creation
strategy is forced.

## Goals

- GDExtension ABI correctness first.
- Keep generated bindings, generated dispatch code, and hand-written policy
  separate.
- Do not force class registration, allocation, or instance lifetime through one
  API.
- Let users opt into automatic behavior with small annotations and helpers.
- Keep the common path small enough that users can replace parts themselves.

## Layers

```text
bindings/          generated raw ABI; no dependency on the runtime
      ^
codegen output     generated dispatcher wrappers, codegen types, virtual metadata
      ^
runtime.zig        process-wide dispatcher/registry state and engine lifecycle
      ^
abi.zig / reflect / annotations / registration / heap.zig
      ^
godot.zig          public facade: re-exports runtime and codegen modules
```

Generated code imports `runtime.zig` as `runtime` for `dispatcher()`/`dispatch()`
and, in generated class helpers, `reflect.inheritsFrom`. This narrow file-level
cycle is intentional: generated wrappers must not depend on annotations or
registration policy. The hand-written runtime layer may depend on generated
artifacts. `godot.zig` is a facade only; user code imports it, generated code
does not. `runtime.zig` and `heap.zig` form one narrow allocator/dispatch cycle.


## Layout

```text
src/entrypoint.zig        example extension entry point; replace this
src/godot/                hand-written runtime layer
  runtime.zig             process-wide dispatcher/registry state and lifecycle
  godot.zig               public facade imported as `godot`
  abi.zig                 canonical ptrcall slot/read/write helpers
  heap.zig                engine-backed allocator
  reflect/                type, hierarchy, object, and function helpers
    reflect.zig
    hierarchy.zig
    meta.zig
    functions.zig
    base.zig
    objects.zig
    extension.zig
    defaults.zig
  annotations/            opt-in markers
    annotations.zig
    base.zig
    on_ready.zig
    property.zig
    init.zig
    marker.zig
    init_callback.zig
    deinit_callback.zig
    notification_callback.zig
    override.zig
    internal/SafeGuard.zig
  registration/           optional lifecycle, virtual, and property registration
    Registry.zig
    ClassRegistration.zig
    instance.zig
    create_instance.zig
    notification.zig
    virtuals.zig
    property.zig
  bindings/               bindgen output + hand-written bindings.zig module root
  classes/                codegen class output (generated)
  builtins/               hand-written and generated builtins
  utility/                generated utility wrappers
  constants.zig
  enums.zig
  native.zig
  singletons.zig
  naming.zig
```

`reflect` contains hand-written reflection helpers. `annotations` contains
opt-in markers. `registration` contains optional lifecycle, virtual dispatch, and
property registration.
`initFieldsDefault` belongs to `reflect/defaults.zig`; annotation field setup
belongs to `annotations.initAnnotFieldsDefault`. Property `.init` values are
creation-time initializers run by `annotations.initPropertyFields`.

## Bootstrap

The example entry point is `src/entrypoint.zig`. Its shape is:

```zig
export fn test_zig_init(
    get_proc_address: gdi.InterfaceGetProcAddress,
    library: gdi.ClassLibraryPtr,
    initialization: *gdi.Initialization,
) callconv(.c) bool {
    if (!godot.init(godot.engine_allocator, get_proc_address, library, initialization)) {
        return false;
    }

    godot.registry().addClasses(
        .{MyClass},
        .{},
        .{ .create_allocator = godot.engine_allocator },
    ) catch return false;

    return true;
}
```

`godot.init` initializes the dispatcher, creates the process-wide `Registry`
arena, sets the minimum initialization level from the build option, and installs
the initialize/deinitialize callbacks. `godot.registry()` is valid only after
`godot.init`.

## Public surface

```zig
const godot = @import("godot");

godot.dispatch(.get_godot_version2, .{&version});
godot.engine_allocator
godot.registry()

godot.runtime.dispatcher()
godot.runtime.richLogFn

godot.classes.core.Node
godot.builtins.Variant
godot.utility.general

godot.reflect.isExtensionClass(T)
godot.reflect.objectTarget(T)
godot.reflect.EngineBaseType(T)
godot.reflect.initFieldsDefault(T, child)

godot.abi.readArgument(T, ptr)
godot.abi.writeReturn(T, ptr, value)

godot.builtins.Variant.wrap(T, value)
godot.builtins.Variant.init(T, value)
godot.builtins.Variant.as(T)
godot.builtins.Variant.objectInstance()
godot.builtins.Variant.isNullObject()
godot.builtins.Variant.typeFor(T)

godot.annotations.OnReady(...)
godot.annotations.Property(T, .{ .usage = ..., .read_only = true, .type = .object })
godot.enums.PropertyUsageFlags.exported
godot.annotations.Init(T, func, args)
godot.annotations.Property(T, options).Init(func, args)
godot.annotations.initPropertyFields(T, Base, owner, base)
godot.annotations.descriptors(T)
godot.annotations.deinitPropertyFields(T, instance)
godot.annotations.Base(Extends)
godot.annotations.Override("_get_cursor_shape", fn)

godot.registration.Registry
godot.Registry
godot.registration.ClassOptions
godot.registration.ClassRegistration
godot.registration.virtuals
```

## What Godot sees

A registered extension class receives:

- `create_instance_func`
- `free_instance_func`
- `notification_func`
- `get_virtual_func`
- `is_exposed = true`
- `set_func` / `get_func` when the class declares at least one
  `annotations.Property` field
- `get_property_list_func` / `free_property_list_func` when at least one
  property has non-zero usage

Extension instance creation uses `classdb_construct_object3` (no implicit
post-initialize, RefCounted refcount 1), attaches the Zig instance, then sends
`NOTIFICATION_POSTINITIALIZE` once when the engine requests it.

`Property` options also include read-only dispatch (`.read_only`) and eager
creation-time values (`.init`, assigned after the `Base` marker and before
`InitCallback`); neither is `OnReady`-coupled or changes cleanup policy.

Virtual overrides, instance construction/free, notifications, and dynamic
property callbacks are wired automatically from the markers. Zig methods, static
ClassDB properties, signals, and integer constants are not registered for
GDScript yet. Adding those surfaces is deliberate work, not an implicit side
effect of registering a class. Property lifetime is explicit: the default setter
manages only known managed builtins and `RefCounted` references, and free-time
cleanup is opt-in through `ClassOptions.auto_property_cleanup` or a manual
`annotations.deinitPropertyFields` call. Dynamic `Property` semantics are
documented in [docs/properties.md](docs/properties.md).

## Boundaries

- Bindgen owns `src/godot/bindings`. Codegen writes only its generated subtrees
  under `src/godot`; it never writes `godot.zig`, `runtime.zig`, or other
  hand-written files.
- Generated bindings do not depend on annotations or registration.
- Generated dispatch code imports `runtime.zig`, never the `godot.zig` facade.
- Codegen does not generate `godot.zig` or `runtime.zig`.
- Annotations are optional. Missing annotations do not prevent registration.
- `Registry` is optional; its creation/free/notification/virtual builders are
  usable directly.
- No forced pooling or creation strategy. `ClassRegistration.create_allocator` and
  `gpa` are inputs, not policy.
- No per-virtual user wrappers. User classes declare normal Zig methods matching
  the generated virtual signature.
- Non-trivial virtual arguments are borrowed; non-trivial virtual returns are
  transferred into engine-owned storage.
- `RefCounted` virtual arguments/returns use `ref_get_object`/`ref_set_object`.
- `is_virtual` and `is_abstract` are deliberately deferred until their callback
  behavior is implemented.

## Start here

1. [docs/architecture.md](docs/architecture.md) - layer boundaries and file ownership.
2. [docs/reflect.md](docs/reflect.md) - reflection helpers and field defaults.
3. [docs/registration.md](docs/registration.md) - class registration, options, lifecycle.
4. [docs/annotations.md](docs/annotations.md) - opt-in marker behavior.
5. [docs/virtuals.md](docs/virtuals.md) - virtual metadata and ABI callbacks.
6. [docs/ownership.md](docs/ownership.md) - borrowed arguments, returned ownership, Variant and RefCounted rules.
7. [docs/variants.md](docs/variants.md) - `Variant` ownership, `wrap`/`init`/`as`, packed arrays, and type mapping.
8. [docs/properties.md](docs/properties.md) - `Property` field annotation, dynamic registration backend, usage flags, and lifetime cleanup.
9. [docs/style.md](docs/style.md) - naming, bottom imports, formatting, and established exceptions.
