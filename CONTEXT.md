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

- **Durable support code** - the hand-written runtime and its tests, generator,
  build helpers, and reference docs. Users should be able to keep these
  unchanged while they write their game.
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
  ownership.zig           engine-object retain/release and constructed-base destruction
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
    property_hint.zig
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
  tests/                  hand-written tests and compile-only checks
    all.zig               test root; imports every test file
    abi.zig
    classes.zig           generated bindings/codegen analysis
    ownership.zig         engine object ownership helpers
    annotations/          tests mirroring the annotation modules
    builtins/             tests mirroring the builtin modules
    reflect/              tests mirroring the reflect modules
    registration/         tests mirroring the registration modules
    live/                 separate dynamic-library tree for test-godot-live; not in all.zig
      entrypoint.zig      entry symbol; registers fixture classes
      live_node.zig       LiveNode fixture class
build/                    build helpers and example scan wiring
  godot.zig               reusable Godot run helper
  generator.zig
  class_files.zig
  tools/class_files_scan_and_gen.zig
build/templates/          reserved for project-generation files (empty today)
generator/                host-side bindgen/codegen generator
generator/docs/           generator-internal design docs
gd_interface/             GDExtension header and JSON inputs
godot-test/               committed minimal Godot 4.8 project for test-godot-live
  project.godot           test project settings
  run_tests.gd            headless SceneTree runner; exit code is the result
  tests/                  GDScript assertion suites
    test_case.gd          shared failures/check/suite-name base
    classdb.gd            registration, signals, constants
    properties.gd         property metadata and value round-trips
  test_extension.gdextension  checked-in descriptor; entry symbol test_extension_init
  lib/                    gitignored; receives the built test extension and PDB
vendor/                   submodule or path dependencies
```

`reflect` contains hand-written reflection helpers (`classNameOf` maps an object
pointer type to its engine class name). `annotations` contains
opt-in markers. `registration` contains optional lifecycle, virtual dispatch,
property registration, and class-level ClassDB metadata. `ownership.zig` is the
engine-object ownership and lifetime primitive: `retainRefCounted` /
`releaseRefCounted` / `retainObjectReference` for `RefCounted` values and
`releaseConstructedBase` for a base constructed by
`classdb_construct_object3`. It depends on `reflect` and `classes`, never on
`annotations` or `registration`. Declared-type Variant work lives on `Variant`
itself: `initDeclared`/`asDeclared` for values and `typeFor` for the Variant type.
`initFieldsDefault` belongs to `reflect/defaults.zig`; annotation field setup
belongs to `annotations.initAnnotFieldsDefault`, which only resets wrapper
defaults and leaves `OnReady` values unresolved. Property `.init` values are
creation-time initializers run by `annotations.initPropertyFields` after the
instance is attached.

`annotations` is a facade; its flat exports are the declaration and lifecycle
API. The `property` and `constants` submodules hold the implementation and
introspection behind them: `godot.annotations.property` exposes
`descriptors`, `layout`, `PropertyDescriptor`, `PropertyValueType`,
getter/setter/deinit introspection, field discovery, and cleanup internals;
`godot.annotations.constants` exposes the `Constants` internals and type-hint
helpers (`typeHint`, `findEnumName`). The flat exports
(`Property`, `PropertyGroups`, `Constants`, `ConstantEntry`, `findConstants`,
`initPropertyFields`, `deinitPropertyFields`, ...) remain the declaration and
lifecycle API that user classes and registration call. `marker`
(`marker.Kind`, `kindOf`, `is`) is also exported for marker-identity checks.

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
godot.classes.core.Node.attachInstance(T, instance) // per engine class
godot.classes.core.Node.detachInstance(T)
godot.classes.core.Node.asInstance(T)
godot.classes.core.Node.typeToken(T)
godot.builtins.Variant
godot.utility.general

godot.reflect.isExtensionClass(T)
godot.reflect.objectTarget(T)
godot.reflect.classNameOf(T)
godot.reflect.isNodeClass(T)
godot.reflect.isResourceClass(T)
godot.reflect.EngineBaseType(T)
godot.reflect.initFieldsDefault(T, child)

godot.abi.readArgument(T, ptr)
godot.abi.writeReturn(T, ptr, value)

godot.ownership.retainRefCounted(T, value)
godot.ownership.releaseRefCounted(T, value)
godot.ownership.retainObjectReference(object)
godot.ownership.releaseConstructedBase(Base, base)
godot.builtins.isManaged(T)

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
godot.annotations.PropertyGroups(.{ ... })
godot.enums.PropertyUsageFlags.exported
godot.annotations.Init(T, func, args)
godot.annotations.Property(T, options).Init(func, args)
godot.annotations.initPropertyFields(T, Base, owner, base)
godot.annotations.property.descriptors(T)
godot.annotations.property.layout(T)
godot.annotations.property.PropertyDescriptor
godot.annotations.deinitPropertyFields(T, instance)
godot.annotations.Base(Extends)
godot.annotations.Override("_get_cursor_shape", fn)
godot.annotations.Signal("health_changed", .{ .{ "health", i32 } })
godot.annotations.findSignals(T)
godot.annotations.Constants(struct { ... })
godot.annotations.findConstants(T)
godot.annotations.ConstantEntry
godot.annotations.constants.typeHint(T)

godot.registration.Registry
godot.Registry
godot.registration.ClassOptions
godot.registration.ClassRegistration
godot.registration.CreateInstance
godot.registration.RecreateInstance
godot.registration.FreeInstance
godot.registration.virtuals
godot.registration.classdb
godot.registration.PostRegistrationCallback
```

## What Godot sees

A registered extension class receives:

- `create_instance_func`
- `recreate_instance_func`
- `free_instance_func`
- `notification_func`
- `get_virtual_func`
- `ClassCreationInfo6` fields from `ClassOptions` (`is_virtual`, `is_exposed`,
  `is_runtime`, `icon_path`)
- `set_func` / `get_func` when the class declares at least one
  `annotations.Property` field
- `get_property_list_func` / `free_property_list_func` when at least one
  property has non-zero usage; the list interleaves `annotations.PropertyGroups`
  sections with the visible fields. Property hints are type-derived (enum,
  bitfield, Node/Resource object pointer); a same-class `Constants` declaration
  only adds the registered `class_name` and enum/bitfield usage bits

Contracts: [properties.md](docs/properties.md#property-groups) and
[properties.md](docs/properties.md#property-hints).

After the class itself, `Registry`'s per-class `post_registration_callback`
registers the class's `Signal` declarations and `Constants` markers (integer
constants, enums, bitpack flags); it is null when the class declares neither.
That callback is invoked by `godot.initialize`, never passed to the engine.

Extension instance creation uses `classdb_construct_object3` (no implicit
post-initialize, RefCounted refcount 1), sets field and annotation defaults and
the `Base` marker, attaches the Zig instance, runs `Property` `.init`
initializers and `InitCallback`, then sends `NOTIFICATION_POSTINITIALIZE` once
when the engine requests it. Hot reload is supported for every class registered
through `Registry` via `recreate_instance_func`; it requires `reloadable = true`
in the `.gdextension` and is editor-only. See
[docs/registration.md](docs/registration.md#hot-reload).

`Property` options also include read-only dispatch (`.read_only`) and eager
creation-time values (`.init`, assigned after the instance is attached and
before `InitCallback`); neither is `OnReady`-coupled or changes cleanup policy.

Virtual overrides, instance construction, recreation and freeing,
notifications, dynamic property callbacks (including `PropertyGroups` sections
and type-derived hints), signals, and integer constants are wired
automatically from the markers. Zig methods and static ClassDB properties are
not registered for GDScript yet. Adding those surfaces is deliberate work, not
an implicit side effect of registering a class; the design is in
[docs/classdb.md](docs/classdb.md). Property lifetime is explicit: the default
setter manages only `godot.builtins.isManaged` builtins, `Variant`, and `RefCounted`
references through `godot.ownership`, and free-time cleanup is opt-in through
`ClassOptions.auto_property_cleanup` or a manual
`annotations.deinitPropertyFields` call. Dynamic `Property` semantics are
documented in [docs/properties.md](docs/properties.md).

## Boundaries

- Bindgen owns `src/godot/bindings`. Codegen writes only its generated subtrees
  under `src/godot`; it never writes `godot.zig`, `runtime.zig`, or other
  hand-written files.
- Generated bindings do not depend on annotations or registration.
- Generated dispatch code imports `runtime.zig`, never the `godot.zig` facade.
- Codegen does not generate `godot.zig` or `runtime.zig`.
- Hand-written unit tests live under `src/godot/tests/`; `all.zig` is the root
  that `zig build test-godot` builds and runs. Implementation modules stay
  test-free; unit tests import the public `godot` facade, not relative parent
  paths. `src/godot/tests/live/` is a separate dynamic-library source tree for
  `test-godot-live` and is not imported by `all.zig`.
- `zig build test` stays a wrapper over `test-godot`; it does not depend on the
  live step or on a Godot executable. `test-godot-live` is opt-in, host-only
  (the target must match the build host), and uses `-Dgodot_bin` when supplied
  (otherwise `addRun` searches PATH). It builds the live tree, seeds the ignored
  `godot-test/.godot/extension_list.cfg`, writes the built library only into
  the gitignored `godot-test/lib/`, and runs `godot-test/run_tests.gd`
  headlessly. The Godot process exit code is the step result. It covers
  headless ClassDB registration metadata (class existence, instantiate/free,
  properties, signals, constants), not editor-only inspector rendering or hot
  reload.
- Annotations are optional. Missing annotations do not prevent registration.
- `ownership.zig` is the only engine-object retain/release path: property
  overwrite/cleanup and Variant conversion call it instead of carrying their own
  reference-count policy. It imports `reflect` and `classes`, never `annotations`
  or `registration`.
- Annotation implementation and introspection helpers live in the
  `annotations/property.zig` and `annotations/constants.zig` submodules; the flat
  `annotations` exports stay the declaration and lifecycle API user classes call.
- `Registry` is optional; its creation, recreation, free, notification, and
  virtual builders are usable directly.
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

1. [docs/build.md](docs/build.md) - build steps, options, the live Godot test,
   generated output, and the template plan.
2. [docs/bindings-only.md](docs/bindings-only.md) - raw bindings without the runtime layer.
3. [docs/architecture.md](docs/architecture.md) - layer boundaries and file ownership.
4. [docs/reflect.md](docs/reflect.md) - reflection helpers and field defaults.
5. [docs/registration.md](docs/registration.md) - class registration, options, lifecycle.
6. [docs/annotations.md](docs/annotations.md) - opt-in marker behavior.
7. [docs/virtuals.md](docs/virtuals.md) - virtual metadata and ABI callbacks.
8. [docs/ownership.md](docs/ownership.md) - borrowed arguments, returned ownership, Variant and RefCounted rules.
9. [docs/variants.md](docs/variants.md) - `Variant` ownership, `wrap`/`init`/`as`, packed arrays, and type mapping.
10. [docs/properties.md](docs/properties.md) - `Property` fields, `PropertyGroups` sections, type-derived hints, usage flags, and lifetime cleanup.
11. [docs/signals.md](docs/signals.md) - signal declarations, registration, typed emit, and argument conversion.
12. [docs/callables.md](docs/callables.md) - custom callable design: Zig closures as engine `Callable`s, identity, and typed connect.
13. [docs/classdb.md](docs/classdb.md) - class-level ClassDB surfaces, methods/constants/property-group decisions, and class modes.
14. [docs/style.md](docs/style.md) - naming, bottom imports, formatting, test placement, and established exceptions.
