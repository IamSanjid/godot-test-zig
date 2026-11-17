# Architecture

## Dependency direction

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

The upward arrows are the normal dependency direction: a lower layer imports a
higher one. `godot.zig` is a facade only: user code imports it, and nothing else
under `src/godot` imports it, so the facade adds no cycle of its own.

Generated wrappers import `runtime.zig` directly as `runtime` for
`dispatcher()`/`dispatch()` and, for generated class helpers,
`reflect.inheritsFrom`. They must not depend on annotations or registration
policy. `runtime.zig` owns the process-wide dispatcher and registry state those
wrappers call into, so generated output and `runtime.zig` are mutually dependent
by design.

The hand-written registration layer imports `runtime.zig` directly for
dispatcher access and imports `reflect`/`annotations` modules directly; it does
not round-trip through the facade. `runtime.zig` imports the registration layer
for the `Registry` type and the builtins/utility modules used by `richLogFn`.
`heap.zig` dispatches through `runtime.zig` while `runtime.richLogFn` allocates
with `heap.engine_allocator`, which leaves one narrow `runtime.zig` <->
`heap.zig` cycle.

These cycles are legal because no edge is needed to compute struct layout or
other comptime information; they are file-level import cycles only. If the
dispatcher cycle is ever removed, split dispatcher access into a small
`dispatch.zig`; do not move lifecycle policy into generated code.

No generated file references annotations or registration.

## Errors and allocation

- Annotation and virtual misuse fail at compile time where possible.
- `godot.init` returns false when dispatcher initialization fails.
- Registration errors such as `DuplicateClassName` should fail the entry symbol.
- A failed `InitCallback` destroys the user instance and engine base.
- `godot.engine_allocator` is the engine-backed allocator.
- The `Registry` arena is allocated from the allocator passed to `godot.init`.
- Per-instance creation uses `AddClassData.create_allocator`; callback allocation
  uses `gpa`, falling back to `create_allocator`.
- Cached `String`/`StringName`/`NodePath` literals are process-lifetime and
  unsynchronized; initialize them before cross-thread use.

## What is generated

`bindings/` is bindgen output. It contains raw ABI wrappers, explicit
`dispatcher: anytype` parameters, interface structs, builtin layouts, and class
methods.

`classes/`, `builtins/generated/`, `utility/`, `constants.zig`, `enums.zig`,
`native.zig`, and `singletons.zig` are codegen output. They add:

- implicit `runtime.dispatcher()` (imported from `runtime.zig`, not `godot.zig`)
- codegen-facing builtin types
- generated builtin `toBinding` / `fromBinding`
- class/virtual metadata
- `MemberFunctions` / `StaticFunctions` metadata

Codegen does not own registration or class-instance lifecycle.

## What is hand-written

- `runtime.zig` — process-wide dispatcher/registry state, engine
  initialize/deinitialize callbacks, `init`, and `richLogFn`.
- `godot.zig` — public facade re-exporting `runtime.zig` and the codegen type
  modules; the entry point imports it as `godot`.
- `abi.zig` — canonical ptrcall widths and shared argument/return marshalling.
- `reflect/` — type predicates, inheritance traversal, function-shape helpers,
  generic field-default initialization.
- `annotations/` — optional markers such as `Base`, `OnReady`, `InitCallback`,
  `DeinitCallback`, `NotificationCallback`.
- `registration/` — optional `Registry`, class creation/free, notification
  dispatch, virtual-method registration.
- `heap.zig` — engine allocator.
- hand-written builtins and the hand-written builtin aggregate.

## Naming decisions

- `reflect`, not `reflection`: shorter and consistent with Zig’s `meta` style.
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

- Do not force an “ABI” convention on user classes beyond the minimum needed to
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

## Demo code

`TestNode` and `test_zig_init` are examples, not library code. They belong in
`entrypoint.zig` or a separate example consumer. `godot.zig` should not ship a
demo class.
