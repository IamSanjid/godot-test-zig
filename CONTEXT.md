# Project context

This repository is a template Godot GDExtension project written in Zig. It
combines generated GDExtension bindings and dispatch wrappers with a small
hand-written runtime layer.

The template is intentionally a starting point, not a framework or package.
Projects clone or fork it and own the whole tree. Generated code and hand-written
policy stay separate, annotations are opt-in, `Registry` is an optional
convenience collector, and no allocation, pooling, or instance-creation strategy
is forced.

## Template model

Three kinds of files live here:

- **Durable support code** - the hand-written runtime, generator, build helpers,
  and reference docs. Users should be able to keep these unchanged while they
  write their game.
- **Example scaffold** - `src/entrypoint.zig`, `src/example/`, the generated
  `src/example.gen.zig` wiring, and example-specific build scan settings. A
  future project-generation step will remove or rewrite these.
- **Generated output** - bindgen/codegen trees and scanned `*.gen.zig` modules.
  Never edit by hand; regenerate with the matching build step.

There is no project-generation step yet. See [docs/build.md](docs/build.md) for
the planned copy contract and [README.md](README.md) for the after-cloning
checklist.

Users can keep the full runtime, use the runtime without `Registry`, or use only
the raw bindings layer ([docs/bindings-only.md](docs/bindings-only.md)).

## Goals

- GDExtension ABI correctness first.
- Stay clone-friendly: a project can own, edit, or remove every layer.
- Keep generated bindings, generated dispatch code, and hand-written policy
  separate.
- Do not force class registration, allocation, or instance lifetime through one
  API.
- Let users opt into automatic behavior with small annotations and helpers.
- Keep the common path small enough that users can replace parts themselves.

## Layers

Layer ownership and import direction are documented in
[docs/architecture.md](docs/architecture.md) and
[docs/build.md](docs/build.md). The invariant: generated code must not depend on
annotations or registration policy; `godot.zig` is a facade only.

## Layout

```text
src/entrypoint.zig        example extension entry point; replace this
src/example/              example extension classes
src/example.gen.zig       generated class-file namespace (ignored)
src/godot/                hand-written runtime plus generated subtrees
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
    signal.zig
    constants.zig
    internal/SafeGuard.zig
  registration/           optional lifecycle, virtual, property, and class-level registration
    registration.zig
    Registry.zig
    ClassRegistration.zig
    instance.zig
    create_instance.zig
    notification.zig
    virtuals.zig
    property.zig
    classdb.zig
  bindings/               bindgen output + hand-written bindings.zig module root
  classes/                codegen class output (generated)
  builtins/               hand-written and generated builtins
  utility/                generated utility wrappers
  constants.zig
  enums.zig
  native.zig
  singletons.zig
  naming.zig
  tests.zig               hand-written runtime tests
build/                    build helpers and example scan wiring
  generator.zig
  class_files.zig
  tools/class_files_scan_and_gen.zig
build/templates/          reserved for project-generation files (empty today)
generator/                host-side bindgen/codegen generator
generator/docs/           generator-internal design docs
gd_interface/             GDExtension header and JSON inputs
vendor/                   submodule or path dependencies
```

`reflect` contains hand-written reflection helpers (`classNameOf` maps an object
pointer type to its engine class name). `annotations` contains
opt-in markers. `registration` contains optional lifecycle, virtual dispatch,
property registration, and class-level ClassDB metadata. Declared-type Variant
work lives on `Variant` itself: `initDeclared`/`asDeclared` for values and
`typeFor` for the Variant type.
`initFieldsDefault` belongs to `reflect/defaults.zig`; annotation field setup
belongs to `annotations.initAnnotFieldsDefault`. Property `.init` values are
creation-time initializers run by `annotations.initPropertyFields`.

## Bootstrap

The example entry point is [src/entrypoint.zig](src/entrypoint.zig). It exports
`test_zig_init`, checks the Godot version, calls `godot.init`, registers the
generated example namespace, and returns the engine initialization callbacks.
The exported symbol must match the `.gdextension` `entry_symbol`.

`godot.init` initializes the dispatcher, creates the process-wide `Registry`
arena, sets the minimum initialization level from the build option, and installs
the initialize/deinitialize callbacks. `godot.registry()` is valid only after
`godot.init`.

## Generated class namespaces

`zig build gen` (and `zig build scan`) scans extension class files and writes
`src/example.gen.zig` with imports like:

```zig
pub const TestNode = @import("example/TestNode.zig");
pub const test_node2 = @import("example/test_node2.zig");
```

`src/entrypoint.zig` passes the generated namespace to
`godot.registry().addClasses(...)`; `ClassOptions.depth` defaults to 2, so a
file-root namespace can contain the extension class. Scanner output is a build
artifact: it is gitignored and must not be edited. See
[README.md](README.md#class-file-scanning) and
[docs/registration.md](docs/registration.md#scanned-class-groups).

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
godot.reflect.classNameOf(T)
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
godot.builtins.Variant.initDeclared(T, value)
godot.builtins.Variant.asDeclared(T)

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
godot.annotations.Signal("health_changed", .{ .{ "health", i32 } })
godot.annotations.findSignals(T)
godot.annotations.Constants(struct { ... })
godot.annotations.findConstants(T)
godot.annotations.ConstantEntry

godot.registration.Registry
godot.Registry
godot.registration.ClassOptions
godot.registration.ClassRegistration
godot.registration.virtuals
godot.registration.classdb
godot.registration.PostRegistrationCallback
```

## What Godot sees

A registered extension class receives:

- `create_instance_func`
- `free_instance_func`
- `notification_func`
- `get_virtual_func`
- `ClassCreationInfo6` fields from `ClassOptions` (`is_virtual`, `is_exposed`,
  `is_runtime`, `icon_path`)
- `set_func` / `get_func` when the class declares at least one
  `annotations.Property` field
- `get_property_list_func` / `free_property_list_func` when at least one
  property has non-zero usage

After the class itself, `Registry`'s per-class `post_registration_callback`
registers the class's `Signal` declarations and `Constants` markers (integer
constants, enums, bitpack flags); it is null when the class declares neither.
That callback is invoked by `godot.initialize`, never passed to the engine.

Extension instance creation uses `classdb_construct_object3` (no implicit
post-initialize, RefCounted refcount 1), attaches the Zig instance, then sends
`NOTIFICATION_POSTINITIALIZE` once when the engine requests it.

`Property` options also include read-only dispatch (`.read_only`) and eager
creation-time values (`.init`, assigned after the `Base` marker and before
`InitCallback`); neither is `OnReady`-coupled or changes cleanup policy.

Virtual overrides, instance construction/free, notifications, dynamic property
callbacks, signals, and integer constants are wired automatically from the
markers. Zig methods and static ClassDB properties are not registered for
GDScript yet. Adding those surfaces is deliberate work, not an implicit side
effect of registering a class; the design and phase plan are in
[docs/classdb.md](docs/classdb.md). Property lifetime is explicit: the default setter
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
- No forced pooling or creation strategy. `ClassRegistration.instance_allocator` and
  `gpa` are inputs, not policy.
- No per-virtual user wrappers. User classes declare normal Zig methods matching
  the generated virtual signature.
- Non-trivial virtual arguments are borrowed; non-trivial virtual returns are
  transferred into engine-owned storage.
- `RefCounted` virtual arguments/returns use `ref_get_object`/`ref_set_object`.
- `is_virtual` is a tooling flag (editor/creation dialogs) with no callback
  behavior, and is implemented; `is_abstract` removes instance creation and is
  not implemented yet.
  [docs/classdb.md](docs/classdb.md#d6-is_virtual-is-a-tooling-flag-only-is_abstract-removes-instances)
  owns the distinction and the ordering.
- The class-file scanner writes only the configured `*.gen.zig` module; it is
  generated by `zig build gen` (or `zig build scan`) and never edited by hand.
- Template generation is not implemented yet. The planned contract is in
  [docs/build.md](docs/build.md); do not treat example wiring as durable API.

## Start here

1. [docs/build.md](docs/build.md) - build steps, options, generated output, template plan.
2. [docs/bindings-only.md](docs/bindings-only.md) - raw bindings without the runtime layer.
3. [docs/architecture.md](docs/architecture.md) - layer boundaries and file ownership.
4. [docs/reflect.md](docs/reflect.md) - reflection helpers and field defaults.
5. [docs/registration.md](docs/registration.md) - class registration, options, lifecycle.
6. [docs/annotations.md](docs/annotations.md) - opt-in marker behavior.
7. [docs/virtuals.md](docs/virtuals.md) - virtual metadata and ABI callbacks.
8. [docs/ownership.md](docs/ownership.md) - borrowed arguments, returned ownership, Variant and RefCounted rules.
9. [docs/variants.md](docs/variants.md) - `Variant` ownership, `wrap`/`init`/`as`, packed arrays, and type mapping.
10. [docs/properties.md](docs/properties.md) - `Property` field annotation, dynamic registration backend, usage flags, and lifetime cleanup.
11. [docs/signals.md](docs/signals.md) - signal declarations, registration, typed emit, and argument conversion.
12. [docs/callables.md](docs/callables.md) - custom callable design: Zig closures as engine `Callable`s, identity, and typed connect.
13. [docs/classdb.md](docs/classdb.md) - class-level ClassDB surfaces, methods/constants/groups design, and class modes.
14. [docs/style.md](docs/style.md) - naming, bottom imports, formatting, and established exceptions.
