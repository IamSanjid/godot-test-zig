# Documentation map

Start with the repository [README](../README.md) and [CONTEXT](../CONTEXT.md),
then use these pages by task.

Status: declared-type conversion, properties (including wrapper-typed containers
and container hints), signals, methods (declaration, registration, and both call
adapters), virtuals, integer constants, and the `godot.collections` typed wrappers
are implemented. Abstract classes (`is_abstract`) are the next engine surface;
their design is in [classdb.md](classdb.md).

## Building and template work

- [build.md](build.md) - steps, build options, generated-output and test layout,
  the optional live Godot test, Godot version updates, and the planned
  project-generation contract.
- [bindings-only.md](bindings-only.md) - using the raw ABI bindings without the
  helpful runtime layer.

## Runtime design

- [architecture.md](architecture.md) - dependency direction, ownership, layer
  boundaries, and the internal-module/test-access rules.
- [registration.md](registration.md) - `Registry`, class options, lifecycle,
  scanned class groups.
- [annotations.md](annotations.md) - opt-in class, field, type, and callback
  markers, plus the `property`/`constants` introspection submodules.
- [conversion.md](conversion.md) - the declared-type conversion model: direct
  support, `Conversion` markers, ownership direction, and Variant vs ptrcall
  consequences.
- [collections.md](collections.md) - typed owning `Array(T)`/`Dictionary(K, V)`
  wrappers, their declared conversion type, ownership, and engine typing
  metadata.
- [virtuals.md](virtuals.md) - virtual metadata and callback behavior.
- [properties.md](properties.md) - dynamic `Property` fields, explicit ownership
  modes, property groups, enum/bitfield and container hints, wrapper-typed
  container properties, and cleanup.
- [signals.md](signals.md) - signal declarations, registration, typed emit, and
  argument conversion.
- [callables.md](callables.md) - custom callable design: Zig closures as engine
  `Callable`s, identity, and typed connect.
- [classdb.md](classdb.md) - class-level surfaces: implemented signals, integer
  constants, methods, property groups, and enum/bitfield hints, plus the class
  modes (`is_virtual` implemented; `is_abstract` designed).
- [ownership.md](ownership.md) - the `Ref`/`Owned`/borrowed ownership model,
  typed construction and create-instance handoff, and the retain/release
  primitives.
- [variants.md](variants.md) - `Variant` borrowed views, conversion, and lifetime.
- [reflect.md](reflect.md) - reflection helpers and field defaults.
- [style.md](style.md) - project naming, comments, imports, formatting, the
  public-facade/internal-module rule, established exceptions, and test placement.

## Generator

Generator-internal documentation lives in
[generator/CONTEXT.md](../generator/CONTEXT.md) and
[generator/docs/](../generator/docs/). It is maintainer-facing; users adapting a
Godot version should use [build.md](build.md) first.
