# Architecture

## Dependency direction

| Layer | May import | Notes |
|---|---|---|
| `bindings/` | `godot_interface` only | Raw ABI wrappers; no runtime or facade dependency. |
| codegen output | `bindings`, `runtime.zig`, `reflect` | Generated dispatcher wrappers, typed classes, virtual metadata. Never imports `godot.zig`, annotations, or registration. |
| `runtime.zig` | `bindings`, codegen builtins/utility, `registration`, `reflect` | Process-wide dispatcher/registry state and engine lifecycle. |
| hand-written support | `runtime.zig`, `bindings`, `reflect` | `abi.zig`, `heap.zig`, annotations, registration helpers. |
| `godot.zig` | `runtime.zig` and codegen modules | Facade only; nothing else imports it. |
| user entrypoint | `godot.zig`, or the raw `bindings` module | The bindings-only path skips the runtime and codegen layers. |

`godot.zig` is a facade only: user code imports it, and nothing else under
`src/godot` imports it, so the facade adds no cycle of its own.

Generated wrappers import `runtime.zig` directly as `runtime` for
`dispatcher()`/`dispatch()` and, for generated class helpers,
`runtime.reflect.inheritsFrom`. They must not depend on annotations or
registration policy. `runtime.zig` owns the process-wide dispatcher and
registry state those wrappers call into, so generated output and `runtime.zig`
are mutually dependent by design.

The hand-written registration layer imports `runtime.zig` directly for
dispatcher access and imports `reflect`/`annotations` modules directly; it does
not round-trip through the facade. `runtime.zig` imports the registration layer
for the `Registry` type and the builtins/utility modules used by `richLogFn`.
`heap.zig` dispatches through `runtime.zig` while `runtime.richLogFn` allocates
with `heap.engine_allocator`, which leaves one narrow `runtime.zig` <-> `heap.zig`
cycle.

These cycles are legal because no edge is needed to compute struct layout or
other comptime information; they are file-level import cycles only. If the
dispatcher cycle is ever removed, split dispatcher access into a small
`dispatch.zig`; do not move lifecycle policy into generated code.

No bindgen/codegen output references annotations or registration. Scanner output
imports user class files and is a separate generated artifact.

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
- A failed `InitCallback` destroys the user instance and engine base.
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
- `godot.zig` - public facade re-exporting `runtime.zig` and the codegen type
  modules; the entry point imports it as `godot`.
- `abi.zig` - canonical ptrcall widths and shared argument/return marshalling.
- `reflect/` - type/object predicates, inheritance traversal, Base-marker
  discovery, function-shape helpers, generic field-default initialization.
- `annotations/` - optional markers such as `Base`, `OnReady`, `Property`,
  `InitCallback`, `DeinitCallback`, `NotificationCallback`.
- `registration/` - optional `Registry`, class creation/free, notification,
  virtual-method registration, and dynamic property callbacks.
- `heap.zig` - engine allocator.
- hand-written builtins and the hand-written builtin aggregate.

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

`godot.zig` is a thin public facade. It re-exports the runtime declarations and
the codegen type modules (`classes`, `builtins`, `utility`, `constants`,
`enums`, `native`, `singletons`) and keeps `godot.richLogFn` for `std_options`.
User code keeps importing `godot`; generated code imports `runtime.zig`
directly, so the generated-to-hand-written dependency does not pass through the
facade.

## Design principles

- Do not force an "ABI" convention on user classes beyond the minimum needed to
  identify an engine class (`Extends`).
- Annotations are opt-in. A class with no annotations still registers.
- `Registry` is a convenience collector, not a requirement.
- Creation, notification, and virtual helpers are individually reusable.
- Generated code provides ABI signatures. Hand-written code decides lifecycle
  and policy.
- Avoid duplicate source-of-truth declarations. Hand-written builtins remain the
  type declaration; generated builtin files are function namespaces.
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
