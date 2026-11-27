# Architecture

## Dependency direction

| Layer | May import | Notes |
|---|---|---|
| `bindings/` | `godot_interface` only | Raw ABI wrappers; no runtime or facade dependency. |
| codegen output | `bindings`, `runtime.zig`, `reflect`, `ownership.zig` | Generated dispatcher wrappers, typed classes, virtual metadata. Classes import `ownership.zig` for typed `construct`/`constructLegacy` and `Ref`-typed engine results. Never imports `godot.zig`, annotations, or registration. |
| `runtime.zig` | `bindings`, codegen builtins/utility, `registration`, `reflect` | Process-wide dispatcher/registry state and engine lifecycle. |
| `abi.zig` | nothing | Dependency-free leaf: canonical scalar/builtin ptrcall slot layout and the read/write helpers. No import, no object or reference rules, no policy. |
| `ptrcall.zig` | `abi.zig`, `bindings`, `reflect`, `runtime.zig` | Internal direct ptrcall slot rules: `RefCounted` reference slots (borrow on read, engine-owned storage on write), extension base/instance resolution, canonical fallback. Shared by the conversion layer and virtual callbacks. |
| `conversion.zig` | `ptrcall.zig`, `abi.zig`, `bindings`, codegen builtins, `reflect`, `annotations/conversion.zig` | Internal declared-type layer: direct support and marker policy, Variant-path primitives, converter bridge, borrowability, and the method-argument ownership gate. Not facade-exported; surfaces and tests only. |
| hand-written support | `runtime.zig`, `bindings`, `reflect` | `heap.zig`, annotations, registration helpers. |
| `ownership.zig` | codegen `classes`, `reflect`, `annotations/conversion.zig` | `Ref`/`Owned` ownership handles for engine objects, low-level retain/release, and typed construction handoff. The `annotations/conversion.zig` import is only for the `Ref` conversion marker, so the direction is ownership -> marker; no runtime or registration dependency. |
| `collections.zig` | codegen builtins, `conversion.zig`, `annotations/conversion.zig` | Typed owning container wrappers; declared conversion types re-exported by the facade. |
| `godot.zig` | `runtime.zig`, codegen modules, and the hand-written public modules | Facade only; nothing else imports it. |
| user entrypoint | `godot.zig`, or the raw `bindings` module | The bindings-only path skips the runtime and codegen layers. |
| `src/godot/tests/` | `godot` (and `bindings` for generated-layer analysis) | Hand-written tests; mirror the module layout, never generated. Internal conversion/ptrcall coverage uses the test-only facade hook. |

`godot.zig` is a facade only: user code imports it, and nothing else under
`src/godot` imports it, so the facade adds no cycle of its own. The facade
exports the user-facing surfaces and modules (`bindings` and `naming` included);
the conversion and ptrcall layers are implementation details behind them and are
not exported (see
[Internal modules and test access](#internal-modules-and-test-access)).

Generated wrappers import `runtime.zig` directly as `runtime` for
`dispatcher()`/`dispatch()` and, for generated class helpers,
`runtime.reflect.inheritsFrom`. Generated class files also import the
hand-written `ownership.zig` for typed constructors and `Ref`-typed engine
results. They must not depend on annotations or registration policy otherwise.
`runtime.zig` owns the process-wide dispatcher and registry state those wrappers
call into, so generated output and `runtime.zig` are mutually dependent by
design.

The hand-written registration layer imports `runtime.zig` directly for
dispatcher access and imports `reflect`/`annotations` modules directly; it does
not round-trip through the facade. It also imports the internal conversion
layer for property and signal metadata/value conversion. `runtime.zig` imports
the registration layer for the `Registry` type and the builtins/utility modules
used by `richLogFn`. `heap.zig` dispatches through `runtime.zig` while
`runtime.richLogFn` allocates with `heap.engine_allocator`, which leaves one
narrow `runtime.zig` <-> `heap.zig` cycle.

`abi.zig` imports nothing; `ptrcall.zig` is the only module that turns
`RefCounted`/extension object pointers into ABI slot reads and writes;
`conversion.zig` owns declared-type policy and delegates the direct ptr path to
`ptrcall.zig`. Adding `reflect` or `runtime` imports to `abi.zig` would break its
leaf role and pull policy into the layout helper.

These cycles are legal because no edge is needed to compute struct layout or
other comptime information; they are file-level import cycles only. The
codegen <-> ownership pair is one of them: generated classes import
`ownership.zig` for typed constructors and `Ref`-typed engine results, while
`ownership.zig` imports the generated `classes` tree for `RefCounted` class
types. Keep the cycle file-level: do not move lifecycle policy into codegen and
do not make `ownership.zig` import the facade or `runtime.zig`. If the dispatcher
cycle is ever removed, split dispatcher access into a small `dispatch.zig`; do
not move lifecycle policy into generated code.

No bindgen/codegen output imports annotations or registration directly. Codegen
output imports the hand-written `ownership.zig` for typed constructors and
`Ref`-typed results; `ownership.zig` in turn imports the `annotations/conversion.zig`
marker module, so that marker is the only annotation code reachable from
generated classes. Scanner output imports user class files and is a separate
generated artifact.

## Template ownership

The repository is a clone-first template, so keep these categories explicit:

| Category | Files | Copy behavior |
|---|---|---|
| durable support | `src/godot/` hand-written files, `build/`, `generator/`, `gd_interface/`, durable docs | Keep in a copied project. |
| example scaffold | `src/entrypoint.zig`, `src/example/`, example scan wiring in `build.zig`, `src/example.gen.zig` | Rewrite or remove during project generation. |
| generated output | bindgen/codegen subtrees, `*.gen.zig` modules | Never edit; regenerate per Godot version/configuration. |

The planned project-generation contract and after-cloning checklist live in
[docs/build.md](build.md) and the repository [README](../README.md).

## Errors and allocation

- Annotation and virtual misuse fail at compile time where possible.
- `godot.init` returns false when dispatcher initialization fails.
- Registration errors such as `DuplicateClassName` should fail the entry symbol.
- A failed `InitCallback` detaches the instance, frees its binding, and destroys
  it; creation also releases the constructed base through its typed handle
  (`Ref`/`Owned` `deinit`). Full property cleanup does not run and
  `DeinitCallback` does not run: a field without a default or `.init` may be
  undefined, so a blanket `deinitPropertyFields` is unsafe. Fields with a custom
  `.init` initializer and `.deinit = .best_effort` get a best-effort value
  cleanup instead; custom hooks and values owned by init code are left alone.
  Known leak limitation on the init-failure path; see
  [registration.md](registration.md#instance-lifecycle).
- `godot.engine_allocator` is the engine-backed allocator.
- The `Registry` arena is allocated from the allocator passed to `godot.init`.
- Per-instance creation uses `ClassRegistration.instance_allocator`; callback
  allocation uses `gpa`, falling back to `instance_allocator`.
- Cached `String`/`StringName`/`NodePath` literals are process-lifetime and
  unsynchronized; initialize them before cross-thread use.

## What is generated

`bindings/` is bindgen output apart from the hand-written `bindings.zig` module
entry point. It contains raw ABI wrappers, explicit `dispatcher: anytype`
parameters, interface structs, builtin layouts, and class methods.

`classes/`, `builtins/generated/`, `utility/`, `constants.zig`, `enums.zig`,
`native.zig`, and `singletons.zig` are codegen output. They add:

- implicit `runtime.dispatcher()` (imported from `runtime.zig`, not `godot.zig`)
- codegen-facing builtin types
- generated builtin `toBinding` / `fromBinding`
- typed `construct()`/`constructLegacy()` returning `ownership.Ref`/`Owned`, and
  `ownership.Ref(Class)` for `RefCounted` engine-method results
- class/virtual metadata
- `MemberFunctions` / `StaticFunctions` metadata

`src/*.gen.zig` class-file namespace modules are produced by the `scan` build
step, already included in `zig build gen`. They are ignored and must be
regenerated, not edited. They import user class files, so scanner output may
reference annotations and registration even though generator output does not.

Codegen does not own registration, class-instance lifecycle, or property
registration.

## What is hand-written

- `runtime.zig` - process-wide dispatcher/registry state, engine
  initialize/deinitialize callbacks, `init`, and `richLogFn`.
- `godot.zig` - public facade re-exporting `runtime.zig`, the codegen type
  modules, and the hand-written user-facing modules; the entry point imports it
  as `godot`. It also declares the test-only `godot.internal` hook.
- `abi.zig` - canonical ptrcall slot widths and shared argument/return
  marshalling for scalars and builtins. Dependency-free: it imports nothing and
  does not know about objects, references, or the conversion model.
- `ptrcall.zig` - direct ptrcall object-slot rules: `RefCounted` reference
  slots and extension base/instance resolution. A ptrcall `RefCounted` argument
  slot is borrowed engine-owned reference storage, and a return slot is
  engine-owned reference storage the write gives a reference to (for a fresh
  object, `init_ref` consumes the creation reference instead of adding one). No
  Variant, marker, property, or signal logic.
- `ownership.zig` - the engine-object ownership module: the
  `godot.ownership.Ref(T)` shared reference-counted handle (declared conversion
  type) and the `godot.ownership.Owned(T)` exclusive manual handle for
  non-`RefCounted` objects, plus the low-level
  `retainRefCounted`/`releaseRefCounted`/`retainObjectReference` primitives.
  `Ref` owns one reference, `Owned` destroys its object, and raw pointers are
  borrowed; typed `Class.construct()`/`constructLegacy()` results use these
  handles. It imports codegen `classes` and `reflect`, plus
  `annotations/conversion.zig` only for the `Ref` conversion marker; it never
  imports `runtime.zig`, `registration`, or the facade. Ownership contract:
  [ownership.md](ownership.md).
- `collections.zig` - typed owning wrappers over the engine `Array`/`Dictionary`
  builtins (`Array(T)`, `Dictionary(K, V)`) with element conversion through the
  internal conversion layer. Each wrapper is a declared conversion type: its
  marker imports `annotations/conversion.zig` and maps it to the container
  builtin, so it can be a property value, and its `Element`/`Key`/`Value`
  declarations feed the property hint resolver. It is a user-facing helper
  re-exported by the facade. See [collections.md](collections.md).
- `conversion.zig` - the internal declared-type conversion layer:
  declared-type support and metadata queries, compile-time support gates, the
  Variant-path primitives, the converter bridge, and the borrowed-Variant
  helpers; the direct ptr path delegates to `ptrcall.zig`. It owns the
  `Conversion` marker support policy (direct support only, no chains, no
  ambiguity). It imports `reflect`, `bindings`, `abi.zig`, `ptrcall.zig`, codegen
  builtins, and the `Conversion` marker; it does not own property, signal, or
  virtual policy, and the facade does not export it.
- `tests/` - hand-written tests and compile-only checks that mirror the module
  layout; `all.zig` is the root used by `zig build test-godot`, and `live/` is
  a separate dynamic-library source tree used by `test-godot-live`.
  `tests/conversion.zig` pins support/metadata and the Variant-path primitives;
  `tests/ptrcall.zig` pins the direct slot rules; annotation tests pin the
  declaration-time gates. Tests reach internal modules through the test-only
  `godot.internal` hook.
- `reflect/` - type/object predicates, inheritance traversal, Base-marker
  discovery, function-shape helpers, generic field-default initialization, and
  the engine class name of an object pointer type (`classNameOf`). Reflection is
  query-only; the conversion layer's engine-class-name query is built on it.
- `annotations/` - optional markers such as `Base`, `OnReady`, `Property`,
  `InitCallback`, `DeinitCallback`, `NotificationCallback`, plus the
  class-level `Signal`, `Method`/`Methods`, `Constants`, and `PropertyGroups`
  markers and the type-attached `Conversion` marker. Every family declares
  `pub const marker = marker.Kind.<family>`; discovery checks the kind and then
  the family's shape. `Init` is not a marker.
- `registration/` - optional `Registry`, class creation, recreation, and free,
  notification, virtual-method registration, dynamic property callbacks, method
  registration and its call adapters, and class-level ClassDB metadata.
- `heap.zig` - engine allocator.
- hand-written builtins and the hand-written builtin aggregate.

The layer root holds the facade and lifecycle files, the engine boundary
primitives (`abi.zig` canonical layout leaf, `ptrcall.zig` object-slot rules,
`ownership.zig` handles), allocation (`heap.zig`), naming (`naming.zig`), and the
internal declared-type conversion layer (`conversion.zig`). The dependency
direction is the table above; the root placement is a build/ownership pin, not
an extra layer. `abi.zig` must stay import-free, and `conversion.zig` stays
internal even though many surfaces import it. A helper owned by a single layer
stays in that layer's directory: property hints are resolved in
`annotations/property_hint.zig`, and `registration/` builds the `PropertyInfo`
table from those descriptors plus the conversion layer's metadata queries.

## Naming decisions

Project-wide naming, import-order, and formatting rules live in
[style.md](style.md). These are maintainer conventions for the durable
runtime and generator; game code may follow or replace them.

- `reflect`, not `reflection`: shorter and consistent with Zig's `meta` style.
- `annotations`, not `annot`: the abbreviation buys little and obscures the
  concept.
- `registration/`, not a `Registry/` implementation directory, because the
  helpers are usable without `Registry`.
- `Registry.zig` remains the central nominal type, while registration helpers
  live beside it under `registration/` rather than being private nested
  implementation files.

## Facade and runtime state

`runtime.zig` owns all process-wide state: the dispatcher globals, the optional
`Registry` global, dispatcher/registry initialization, the engine
initialize/deinitialize callbacks, `init`, and `richLogFn`. It exposes
`dispatch`, `dispatcher`, and `reflect`, which is the generated-code import
contract.

`godot.zig` is a thin public facade. It re-exports the runtime declarations, the
codegen type modules (`classes`, `builtins`, `utility`, `constants`, `enums`,
`native`, `singletons`), the generated `bindings` module and `naming`, and the
hand-written user-facing modules (`annotations`, `ownership`, `collections`,
`abi`), and keeps `godot.richLogFn` for `std_options`. Only the user API is
exported: implementation modules such as `conversion.zig`, `ptrcall.zig`, and the
property/registration internals are reachable only through their owning surface.
User code keeps importing `godot`; generated code imports `runtime.zig` directly
(and `ownership.zig` for typed constructors), so the
generated-to-hand-written dependency does not pass through the facade.

## Internal modules and test access

- `conversion.zig` and `ptrcall.zig` are internal layers. They are imported
  directly by the hand-written surfaces that need them (annotations, signals,
  registration, collections) and are not part of the facade's public surface.
- `abi.zig` is the exception among the low-level helpers: it stays exported as
  `godot.abi` because it is a self-contained canonical layout primitive. It
  carries no object/reference policy; `RefCounted` and extension slot rules are
  `ptrcall.zig` concerns and must not be added to `abi.zig`.
- Tests need direct coverage of the internal layers. `godot.zig` therefore
  declares a test-only hook:

  ```zig
  pub const internal = if (builtin.is_test) struct {
      pub const conversion = @import("conversion.zig");
      pub const ptrcall = @import("ptrcall.zig");
  } else struct {};
  ```

  `builtin.is_test` propagates into imported modules, so `godot.internal` has
  the two modules in test builds and is an empty struct otherwise. Unit tests
  use `godot.internal.conversion`/`godot.internal.ptrcall`; normal user builds
  cannot reach either. This is a test path, not API: do not document, re-export,
  or depend on it from user code.
- Implementation modules stay test-free; only files under `src/godot/tests/`
  reference the internal hook. Tests still import the public `godot` facade for
  everything else.

## Design principles

- Do not force an "ABI" convention on user classes beyond the minimum needed to
  identify an engine class (`Extends`).
- Annotations are opt-in. A class with no annotations still registers.
- `Registry` is a convenience collector, not a requirement.
- Creation, recreation, free, notification, and virtual helpers are individually reusable.
- Generated code provides ABI signatures. Hand-written code decides lifecycle
  and policy.
- Avoid duplicate source-of-truth declarations. Hand-written builtins remain the
  type declaration; generated builtin files are function namespaces.
- Engine-facing surfaces share one internal conversion layer. Declared-type
  support, engine/Variant type, engine class name, and value conversion live in
  `conversion.zig`; ptrcall object-slot rules live in `ptrcall.zig`; a surface
  asks those layers instead of reimplementing a declared-type rule.
- The facade exports user surfaces, not implementation: internal modules stay
  internal, and only the test-only `godot.internal` hook reaches them. Canonical
  ABI layout stays in the dependency-free `abi.zig` leaf.
- Avoid per-virtual user wrappers. User classes declare normal Zig methods with
  generated virtual signatures; registration supplies the C callback.

## Example scaffold

`src/entrypoint.zig`, `src/example/`, and the generated `src/example.gen.zig`
are a working example, not durable runtime API. Replace the entry symbol, class
scan paths, and example registration when starting a project. `godot.zig` must
not acquire example-only declarations; keep demo classes in `src/example/`.

`USAGE_SKETCH.md` is a historical design sketch, not current API. Use
[docs/build.md](build.md) and [docs/registration.md](registration.md) for the
implemented behavior.
