# Documentation map

Start with the repository [README](../README.md) and [CONTEXT](../CONTEXT.md),
then use these pages by task.

## Building and template work

- [build.md](build.md) - steps, build options, generated-output layout, Godot
  version updates, and the planned project-generation contract.
- [bindings-only.md](bindings-only.md) - using the raw ABI bindings without the
  helpful runtime layer.

## Runtime design

- [architecture.md](architecture.md) - dependency direction, ownership, and
  scaffold boundaries.
- [registration.md](registration.md) - `Registry`, class options, lifecycle,
  scanned class groups.
- [annotations.md](annotations.md) - opt-in class, field, and callback markers.
- [virtuals.md](virtuals.md) - virtual metadata and callback behavior.
- [properties.md](properties.md) - dynamic `Property` fields and cleanup.
- [ownership.md](ownership.md) - borrowed arguments and ownership transfer.
- [variants.md](variants.md) - `Variant` conversion and lifetime.
- [reflect.md](reflect.md) - reflection helpers and field defaults.
- [style.md](style.md) - project naming and comment rules.

## Generator

Generator-internal documentation lives in
[generator/CONTEXT.md](../generator/CONTEXT.md) and
[generator/docs/](../generator/docs/). It is maintainer-facing; users adapting a
Godot version should use [build.md](build.md) first.
