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
annotations or registration policy; generated class files may import the
hand-written `ownership.zig` for typed constructors and `Ref`-typed results (its
`annotations/conversion.zig` marker import is the only path to annotations), and
`godot.zig` is a facade only.

## Ownership invariant

The handle model is stated once in [docs/ownership.md](docs/ownership.md). The
runtime rules that shape this code:

- `Ref(T)` is the shared `RefCounted` handle (`empty`, `init`, `clone`, `take`,
  `get`, `isNull`, `deinit`); `Owned(T)` is exclusive manual ownership for
  non-`RefCounted` objects; raw `?*T`/`*T` and `Base(T)` are borrowed.
- `Class.construct()`/`constructLegacy()` return the typed handle, taking over
  the raw creation pointer/reference. `Property` stores `Ref(T)`, never a raw
  `RefCounted` pointer; generated engine-method results use `Ref(T)`; their
  arguments stay raw and borrowed. Create-instance hands a successful base to the
  engine with `.take()` and releases a failed one with `.deinit()`.
- On init failure, creation and recreation detach and destroy the Zig instance,
  and creation also releases the base. The framework does not run
  `deinitPropertyFields` and `DeinitCallback` does not run: fields without a
  default or `.init` may still be undefined, so a blanket walk would read
  garbage. Instead it runs a best-effort cleanup of fields with a custom `.init`
  initializer and `.deinit = .best_effort` while the instance is still attached;
  custom hooks (`fn (*Owner, *T) void`) and fields without a custom initializer
  are untouched, and
  `InitCallback` owns everything it created (known leak limitation on the
  init-failure path; revisit only with initialized-field tracking).
- Virtual callback arguments and returns are raw borrowed pointers: the engine
  return slot is `RefCounted` reference storage and takes the returned object.
  A fresh constructed return moves its creation reference out through a local
  wrapper (`var value = Class.construct(); return value.take();`); calling
  `.take()` on the temporary does not compile.
- Signal emit borrows a call-scoped `Variant` view for inline/plain values,
  managed inline builtins, `Variant`, and object pointers, `RefCounted` included;
  borrowed object views pin no reference, so the Zig caller must keep its own
  reference alive through the synchronous emit. Owning Variants (deinitialized
  after dispatch) exist only for engine-owned storage: heap builtins, packed
  arrays, and managed-engine converters. Borrowed views are never deinitialized
  or stored; deferred connections copy and retain their arguments.
- Consumers do not manage reference counts directly: properties use `.set`/
  `.deinit` modes, signals release only their owning temporaries.

## Layout

```text
src/entrypoint.zig        example extension entry point; replace this
src/example/              example extension classes
src/example.gen.zig       generated class-file namespace (ignored)
src/godot/                hand-written runtime plus generated subtrees
  runtime.zig             process-wide dispatcher/registry state and lifecycle
  godot.zig               public facade imported as `godot`; test-only `internal` hook
  abi.zig                 dependency-free canonical scalar/builtin ptrcall slot layout
  ptrcall.zig             internal direct ptrcall object-slot rules (RefCounted reference slots, extension base/instance)
  heap.zig                engine-backed allocator
  ownership.zig           Ref/Owned handles, typed-construct ownership, and engine-object retain/release primitives
  conversion.zig          internal declared-type support, Variant-path conversion, converter bridge, borrowability
  collections.zig         typed owning Array/Dictionary wrappers; declared conversion types
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
    conversion.zig        Conversion marker for custom value types
    on_ready.zig
    property.zig
    property_hint.zig
    init.zig
    marker.zig            shared marker identity (Kind, kindOf, is)
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
    abi.zig               canonical slot-layout leaf
    classes.zig           generated bindings/codegen analysis
    collections.zig       typed container wrappers, conversion, and hints (compile-only)
    conversion.zig        declared-type conversion contract and compile-only coverage
    ptrcall.zig           direct ptrcall slot rules (compile-only)
    ownership.zig         Ref/Owned handles, retain/release primitives, and compile-only contracts
    annotations/          tests mirroring the annotation modules
    builtins/             tests mirroring the builtin modules
    reflect/              tests mirroring the reflect modules
    registration/         tests mirroring the registration modules
    live/                 separate dynamic-library tree for test-godot-live; not in all.zig
      entrypoint.zig      entry symbol; registers fixture classes
      live_node.zig       LiveNode fixture class
      live_owned_node.zig LiveOwnedNode Owned-handle fixture class
      live_resource.zig   LiveResource object-element fixture class
      live_typed_node.zig LiveTypedNode typed-container and Ref-property fixture class
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
    collections.gd        typed container metadata, typing, and round-trips
    ownership.gd          Owned deinit/take and Ref property paths
    properties.gd         property metadata and value round-trips
    signals.gd            signal emit delivery, including borrowed arguments
  test_extension.gdextension  checked-in descriptor; entry symbol test_extension_init
  lib/                    gitignored; receives the built test extension and PDB
vendor/                   submodule or path dependencies
```

`reflect` contains hand-written, query-only reflection helpers (`classNameOf` is
the final object-pointer name lookup used by the conversion layer's
engine-class-name query). `annotations` contains opt-in markers.
`registration` contains optional lifecycle, virtual dispatch,
property registration, and class-level ClassDB metadata. `conversion.zig` is the
**internal** declared-type layer behind every engine-facing surface: direct
support and metadata queries, the compile-time support gates, the Variant-path
conversion primitives, the converter bridge, and borrowed-Variant helpers; its
direct ptr path delegates to `ptrcall.zig`. It owns the `Conversion` marker
support policy; the marker itself is `annotations/conversion.zig`, exported as
`godot.annotations.Conversion`. Property registration, virtual callbacks,
signal registration/emit, and the typed container wrappers use it, and methods
will. `conversion.zig` and `ptrcall.zig` are not re-exported by the facade: the
only non-test path is the surface APIs, and tests reach them through the
test-only `godot.internal` hook.
`collections.zig` is the typed container module: `Array(T)` and
`Dictionary(K, V)` each own one engine handle, convert elements through the
internal conversion layer, and set the engine typing metadata once with
`setTypedAs` when the container is created. Each wrapper is also a declared
conversion type: a
`Conversion` marker maps it to the engine `builtins.Array`/`builtins.Dictionary`
on both the Variant and ptrcall paths, and its public `Element`/`Key`/`Value`
declarations are read by `annotations/property_hint.zig` to derive container
hints. Public surface: `init`/`deinit`/`fromEngine`/`toEngine`/`clone` plus the
per-kind accessors. `fromEngine` takes over an owned handle, while the conversion
adapter retains from the engine (the Variant intermediate is released and a
ptrcall slot value is borrowed), so a decoded wrapper owns one reference its
consumer must release; `toEngine` returns another owned handle to the same
container.
`ownership.zig` is the engine-object ownership module: the
`godot.ownership.Ref(T)` shared reference-counted handle (`empty`, `init` retains,
`clone` takes another reference, `take` moves the reference out, `get` borrows,
`isNull`, `deinit` releases) and the `godot.ownership.Owned(T)` exclusive manual
handle for non-`RefCounted` objects (`empty`, `get`, `take`, `isNull`, `deinit`
destroys through `Object.destroy`), plus the low-level
`retainRefCounted`/`releaseRefCounted`/`retainObjectReference` primitives.
`retainObjectReference` takes `*classes.core.RefCounted`; non-`RefCounted`
pointers are rejected there rather than risking a refcount on an untracked
object. `Ref` is a declared conversion type; `Owned` is not, and is only for
unparented objects that nothing else owns. `Class.construct()`/`constructLegacy()`
return the typed handle; raw object pointers are borrowed. The module imports
`reflect` and codegen `classes`, plus `annotations/conversion.zig` only for the
`Ref` conversion marker; it has no `runtime.zig` or `registration` dependency.
The contract is in [docs/ownership.md](docs/ownership.md).
The underlying Variant declared-type operations
stay on `Variant`: `initDeclared`/`asDeclared` for values and `typeFor` for the
Variant type. The borrowed form is `Variant.borrow`/`canBorrow`, returning a non-owning
`Variant.Borrowed` view (`inner`, `get`, `getPtrConst`; never deinit or store);
the internal conversion layer composes the declared-type operations for
engine-facing surfaces and writes its raw call-scoped Variant with
`Variant.borrow(...).get()`. The raw bindings have a separate
`bindings.builtins.Variant.borrow(dispatcher, T, value)` helper that returns a
raw binding Variant. Direct ptrcall object-slot rules live in `ptrcall.zig`,
not in `abi.zig`.
`initFieldsDefault` belongs to `reflect/defaults.zig`; annotation field setup
belongs to `annotations.initAnnotFieldsDefault`, which only resets wrapper
defaults and leaves `OnReady` values unresolved. Property `.init` values are
creation-time initializers run by `annotations.initPropertyFields` after the
instance is attached.

`annotations` is a facade; its flat exports are the declaration and lifecycle
API. The `property` and `constants` submodules hold the implementation and
introspection behind them: `godot.annotations.property` exposes
`descriptors`, `layout`, `PropertyDescriptor`, `PropertyValueType`,
getter/setter/deinit introspection (a custom `.deinit` hook is
`fn (*Owner, *T) void`, and `deinitFn` resolves it), the explicit ownership
helpers (`requiresExplicitOwnership`, `setBestEffort`, `deinitBestEffort`), field
discovery, and cleanup internals; `godot.annotations.constants` exposes the
`Constants` internals and type-hint helpers (`typeHint`, `findEnumName`). The
flat exports
(`Property`, `PropertyGroups`, `Constants`, `ConstantEntry`, `findConstants`,
`initPropertyFields`, `deinitPropertyFields`, ...) remain the declaration and
lifecycle API that user classes and registration call. `marker`
(`marker.Kind`, `kindOf`, `is`) is also exported for marker-identity checks.
Every annotation family declares `pub const marker = marker.Kind.<family>`: the
field wrappers `Base`/`OnReady`/`Property`, and the declaration/type markers
`InitCallback`/`DeinitCallback`/`NotificationCallback`/`Signal`/`Constants`/
`PropertyGroups`/`Override`/`Conversion`. Discovery checks the kind and the
family's structural shape. `Init` is not a marker; Base discovery stays
structural in `reflect/base.zig` so it can run without annotations.

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

godot.bindings                    // generated bindings module
godot.naming

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
// No conversion API: declared-type conversion and ptrcall object-slot rules are
// internal. Test builds reach them via godot.internal.conversion / .ptrcall;
// that hook is empty in normal builds and is not API.

godot.collections.Array(T)
godot.collections.Array(T).Element
godot.collections.Dictionary(K, V)
godot.collections.Dictionary(K, V).Key
godot.collections.Dictionary(K, V).Value

godot.ownership.Ref(T)
godot.ownership.Ref(T).init(borrowed)
godot.ownership.Ref(T).clone()
godot.ownership.Ref(T).take()
godot.ownership.Ref(T).deinit()
godot.ownership.Ref(T).get()
godot.ownership.Ref(T).empty
godot.ownership.Ref(T).isNull()
godot.ownership.Owned(T)
godot.ownership.Owned(T).take()
godot.ownership.Owned(T).deinit()
godot.ownership.Owned(T).get()
godot.ownership.Owned(T).empty
godot.ownership.Owned(T).isNull()

godot.classes.core.Resource.construct()  // Ref(Class) for RefCounted classes
godot.classes.core.Node.construct()      // Owned(Class) otherwise

godot.ownership.retainRefCounted(T, value)
godot.ownership.releaseRefCounted(T, value)
godot.ownership.retainObjectReference(ref_counted) // takes *classes.core.RefCounted
godot.builtins.isManaged(T)

// Generated container methods (call them on an Array/Dictionary value).
godot.builtins.Array.setTyped(T, script)
godot.builtins.Array.setTypedAs(variant_type, class_name, script)
godot.builtins.Dictionary.setTyped(K, V, key_script, value_script)
godot.builtins.Dictionary.setTypedAs(key_type, key_class_name, key_script, value_type, value_class_name, value_script)

godot.builtins.Variant.borrow(T, value)
godot.builtins.Variant.canBorrow(T)
godot.builtins.Variant.Borrowed.inner
godot.builtins.Variant.Borrowed.get()
godot.builtins.Variant.Borrowed.getPtrConst()
godot.builtins.Variant.init(T, value)
godot.builtins.Variant.as(T)
godot.builtins.Variant.objectInstance()
godot.builtins.Variant.isNullObject()
godot.builtins.Variant.typeFor(T)
godot.builtins.Variant.initDeclared(T, value)
godot.builtins.Variant.asDeclared(T)
godot.builtins.Variant.clone()

godot.annotations.Conversion(.{ .engine = ..., .to_engine = ..., .from_engine = ... })
godot.annotations.marker.Kind
godot.annotations.marker.kindOf(T)
godot.annotations.marker.is(T, .property)
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
godot.annotations.property.requiresExplicitOwnership(T)
godot.annotations.property.setBestEffort(T, &field, value)
godot.annotations.property.deinitBestEffort(T, &field)
godot.annotations.deinitPropertyFields(T, instance)
godot.annotations.Base(Extends)
godot.annotations.Override("_get_cursor_shape", fn)
godot.annotations.Signal("health_changed", .{ .{ "health", i32 }, .{ "duration", Duration } })
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
godot.registration.Notification
godot.registration.notification
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
  bitfield, Node/Resource object pointer) or declared container metadata (a
  wrapper's `Element`/`Key`/`Value` declarations, or `Array` `.element` and
  `Dictionary` `.key`/`.value` options). An explicit option merges per side with
  the wrapper declarations; hints for converter element/side types resolve
  through their engine representation, so an enum/bitfield engine keeps the
  enum/flags hint string. A same-class `Constants` declaration only adds the
  registered `class_name` and enum/bitfield usage bits.

Property list metadata, set/get value conversion, signal argument metadata and
encoding, and virtual argument/return slots go through the internal conversion
layer (direct ptrcall slots through `ptrcall.zig`, canonical layout through
`abi.zig`). Container hints use the engine container type-string format
(`<Variant type>/<hint>:<text>` per side, `;` between dictionary sides) and are
metadata only: the stored container keeps its own engine typing. The wrapper
declarations supply the same element/side types the explicit options take.
Contracts: [properties.md](docs/properties.md#property-groups),
[properties.md](docs/properties.md#property-hints), and
[collections.md](docs/collections.md#typing); signal metadata in
[signals.md](docs/signals.md#registration).

After the class itself, `Registry`'s per-class `post_registration_callback`
registers the class's `Signal` declarations and `Constants` markers (integer
constants, enums, bitpack flags); it is null when the class declares neither.
That callback is invoked by `godot.initialize`, never passed to the engine.
Signal argument names stay engine names, while each argument's `PropertyInfo`
type and class name come from the internal conversion layer (`Variant` registers
as untyped `.nil`).

Extension instance creation builds the base with `Base.construct()`, which
returns the base's typed handle (`Ref(Base)` for a `RefCounted` base,
`Owned(Base)` otherwise) from `classdb_construct_object3` (no implicit
post-initialize; RefCounted refcount 1). It sets field and annotation defaults
and the `Base` marker, attaches the Zig instance, runs `Property` `.init`
initializers and `InitCallback`, then sends `NOTIFICATION_POSTINITIALIZE` once
when the engine requests it. Creating a base and the engine's create-instance
contract agree on the RefCounted refcount, so the factory hands the base to the
engine with `.take()` on success and releases it with `.deinit()` on failure.
On an `InitCallback` error, creation and recreation detach and destroy the Zig
instance (creation also releases the base); the framework does not run
`deinitPropertyFields` and `DeinitCallback` does not run, because fields without
a default or `.init` may be undefined. It runs a partial best-effort cleanup of
fields with a custom `.init` initializer and `.deinit = .best_effort`; custom
hooks, fields without a custom initializer, and values owned by init code are
left alone. `InitCallback` owns its failure cleanup; `.init` values on a
custom-hook field remain a known leak, revisited only with initialized-field
tracking. After creation the engine owns the base and `free_instance` is its
destructor hook. Hot reload is supported for every class registered through
`Registry` via `recreate_instance_func`; it requires `reloadable = true` in the
`.gdextension` and is editor-only. See
[docs/registration.md](docs/registration.md#hot-reload).

`Property` options also include read-only dispatch (`.read_only`), explicit
ownership modes (`.set` and `.deinit` accept `.best_effort` or a function; a
custom `.deinit` is `fn (*Owner, *T) void`), and eager creation-time values
(`.init`, assigned after the instance is attached and before `InitCallback`);
`.set`/`.deinit` choose the value lifetime policy, while `.init` is not
`OnReady`-coupled and does not change that policy. Each field's conditional
`Property.deinit` method is the per-field cleanup route (custom: owner argument,
`.best_effort`: no arguments, `.none`: `void`); `deinitPropertyFields` is the
all-fields walk.

Virtual overrides, instance construction, recreation and freeing,
notifications, dynamic property callbacks (including `PropertyGroups` sections
and type-derived hints), signals, and integer constants are wired
automatically from the markers. Signal emit borrows a call-scoped Variant view
for inline/plain values, managed inline builtins, `Variant`, and object pointers
(`RefCounted` included; the caller keeps its own reference alive through the
synchronous dispatch), and builds owning Variants (deinitialized after dispatch)
only for engine-owned storage: heap-backed builtins, packed arrays, and
managed-engine converters. The declared Zig values keep their own ownership.
Zig methods and static ClassDB properties are
not registered for GDScript yet. Adding those surfaces is deliberate work, not
an implicit side effect of registering a class; the design is in
[docs/classdb.md](docs/classdb.md). Property lifetime is explicit per field:
`.set` and `.deinit` accept `.best_effort` or a function; a custom `.deinit`
hook is `fn (*Owner, *T) void`, and non-trivial value types
must declare `.deinit` and (unless read-only) `.set`. `RefCounted` storage uses
`godot.ownership.Ref(T)` (a raw pointer is rejected; `Owned` is not property
storage), and `.best_effort` applies the type-driven preset. Free-time cleanup is
opt-in through `ClassOptions.auto_property_cleanup` or a manual
`annotations.deinitPropertyFields` call; a custom hook receives the owner and
`&field.value`. Rules:
[docs/properties.md](docs/properties.md#ownership-modes).

## Boundaries

- Bindgen owns `src/godot/bindings`. Codegen writes only its generated subtrees
  under `src/godot`; it never writes `godot.zig`, `runtime.zig`, or other
  hand-written files.
- Generated bindings do not depend on annotations or registration.
- Generated dispatch code imports `runtime.zig`, never the `godot.zig` facade;
  generated class files also import the hand-written `ownership.zig` for typed
  constructors and `Ref`-typed engine results.
- Codegen does not generate `godot.zig` or `runtime.zig`.
- Hand-written unit tests live under `src/godot/tests/`; `all.zig` is the root
  that `zig build test-godot` builds and runs. Implementation modules stay
  test-free; unit tests import the public `godot` facade, not relative parent
  paths, and reach the internal conversion/ptrcall layers only through the
  test-only `godot.internal` hook (empty in normal builds; not API).
  `src/godot/tests/live/` is a separate dynamic-library source tree for
  `test-godot-live` and is not imported by `all.zig`.
- `zig build test` stays a wrapper over `test-godot`; it does not depend on the
  live step or on a Godot executable. `test-godot-live` is opt-in, host-only
  (the target must match the build host), and uses `-Dgodot_bin` when supplied
  (otherwise `addRun` searches PATH). It builds the live tree, seeds the ignored
  `godot-test/.godot/extension_list.cfg`, writes the built library only into
  the gitignored `godot-test/lib/`, and runs `godot-test/run_tests.gd`
  headlessly. The Godot process exit code is the step result. It covers
  headless ClassDB registration metadata (class existence, instantiate/free,
  properties, signals, constants), signal emit delivery, wrapper-typed container
  hint metadata, engine typing, and set/get round-trips, and the `Owned`
  deinit/take paths, not editor-only inspector rendering or hot reload.
- Annotations are optional. Missing annotations do not prevent registration.
- Every annotation family uses the same `marker.Kind` identity: field wrappers
  (Base/OnReady/Property) and declaration or type markers (InitCallback,
  DeinitCallback, NotificationCallback, Signal, Constants, PropertyGroups,
  Override, Conversion). Discovery checks the kind and still applies the family's
  structural shape validation; the kind is identity, not payload validation.
  `Init` is not a marker, and Base discovery stays structural in
  `reflect/base.zig` so `Variant` and registration can run without annotations.
- `ownership.zig` defines the `Ref` shared handle (declared conversion type) and
  the `Owned` exclusive handle for unparented, non-`RefCounted` objects, plus the
  low-level retain/release primitives. Typed construct results, `Property`
  `.set`/`.deinit` modes, and generated engine-method returns use the handles
  instead of carrying their own reference-count policy. It imports `reflect` and
  codegen `classes`, plus `annotations/conversion.zig` only for the `Ref`
  conversion marker (a deliberate one-way dependency); no `runtime.zig` or
  `registration` import. The codegen <-> ownership cycle is intentional; see
  [docs/architecture.md](docs/architecture.md#dependency-direction).
- `conversion.zig` is the internal conversion layer for properties, signals,
  virtuals, typed container element conversion, and future methods: declared-type
  support, engine/Variant type and class name, borrowability, and the Variant-path
  conversion primitives live there, not in each surface. Its direct ptrcall path
  delegates to `ptrcall.zig`, which owns the `RefCounted` reference-slot and
  extension base/instance rules; `abi.zig` stays a dependency-free leaf for
  canonical scalar/builtin slot layout only. Neither `conversion.zig` nor
  `ptrcall.zig` is facade-exported. The type-attached `Conversion` marker extends
  support for a custom type; the declaration name is free. Converters have no
  chains, and a marker on an already directly supported type is ignored.
- Typed container wrappers are declared conversion types:
  `godot.collections.Array(T)`/`Dictionary(K, V)` own one engine handle each,
  convert elements through the internal conversion layer, and carry a
  `Conversion` marker whose engine type is the container builtin. Properties
  store the wrapper itself and derive container hints from its
  `Element`/`Key`/`Value` declarations (`builtins.Array`/`Dictionary` storage
  instead uses `.element`/`.key`/`.value` options). Engine typing is set once on
  an empty, unshared container (`Array.setTyped`/`Array.setTypedAs`,
  `Dictionary.setTyped`/`Dictionary.setTypedAs`) and cannot change afterwards. A decoded
  wrapper owns one reference on the ptrcall path and the consumer must release
  it. [docs/collections.md](docs/collections.md) owns the contract.
- Annotation implementation and introspection helpers live in the
  `annotations/property.zig` and `annotations/constants.zig` submodules; the flat
  `annotations` exports stay the declaration and lifecycle API user classes call.
- `Registry` is optional; its creation, recreation, free, notification, and
  virtual builders are usable directly.
- No forced pooling or creation strategy. `ClassRegistration.instance_allocator` and
  `gpa` are inputs, not policy.
- No per-virtual user wrappers. User classes declare normal Zig methods matching
  the generated virtual signature.
- Virtual signatures stay raw borrowed pointers, including for `RefCounted`
  objects: the engine slot is `RefCounted` reference storage and takes the
  returned object, so the callback hands over no wrapper. A fresh constructed
  return moves the creation reference out through a local wrapper:
  `var value = Class.construct(); return value.take();`.
- `is_virtual` is a tooling flag (editor/creation dialogs) with no callback
  behavior, and is implemented; `is_abstract` removes instance creation and is
  not implemented yet.
  [docs/classdb.md](docs/classdb.md#d6-is_virtual-is-a-tooling-flag-only-is_abstract-removes-instances)
  owns the distinction and the ordering.
- Next engine surfaces, in order: methods (`Method`/`Methods` registration plus
  call and ptrcall adapters), abstract classes (`is_abstract`), and callables.
  Typed container wrappers already have a ptrcall representation through their
  marker; method argument-release handling for decoded owned values is deferred
  until methods consume containers. Virtual signatures use engine-defined types,
  so a converter cannot appear there and no virtual release path is needed.
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
8. [docs/ownership.md](docs/ownership.md) - the `Ref`/`Owned`/borrowed ownership model, typed construction and create-instance handoff, and the retain/release primitives.
9. [docs/variants.md](docs/variants.md) - `Variant` ownership, `borrow`/`init`/`as`, packed arrays, and type mapping.
10. [docs/conversion.md](docs/conversion.md) - the declared-type conversion model: direct support, `Conversion` markers, ownership direction, Variant vs ptrcall consequences, and containers.
11. [docs/collections.md](docs/collections.md) - typed owning `Array(T)`/`Dictionary(K, V)` wrappers, their declared conversion type, engine typing metadata, and ownership.
12. [docs/properties.md](docs/properties.md) - `Property` fields, `PropertyGroups` sections, type-derived and container hints, usage flags, explicit ownership modes, and lifetime cleanup.
13. [docs/signals.md](docs/signals.md) - signal declarations, registration, typed emit, and argument conversion.
14. [docs/callables.md](docs/callables.md) - custom callable design: Zig closures as engine `Callable`s, identity, and typed connect.
15. [docs/classdb.md](docs/classdb.md) - class-level ClassDB surfaces, methods/constants/property-group decisions, and class modes.
16. [docs/style.md](docs/style.md) - naming, bottom imports, formatting, test placement, and established exceptions.
