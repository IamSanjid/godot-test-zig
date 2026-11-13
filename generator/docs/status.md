# Current status and open issues

## Implemented

- single `generator` executable with `bindgen` and `codegen` subcommands
- shared model for parsing, resolution, docs, defaults, names, types, enums and
  result initialization
- bindgen interface/class/builtin/utility/global/native/singleton output
- codegen classes, utility, generated builtins, constants/enums/native/singletons
- hand-written builtins emit top-level function wrappers instead of duplicate
  `extern struct` declarations
- `MemberFunctions` / `StaticFunctions` metadata aliases generated functions
- class/builtin/utility custom overlays
- class/builtin template replacements and additions
- `@templates_for` class/builtin targeting, including derived class selectors
- relative runtime import from `<out_dir>/godot.zig`
- warning-and-ignore behavior for unsupported artifact overlays
- builtin enum doc inference, including `Basis.from_euler`'s `order`
- correct bitfield backing width and ptrcall slots
- virtual `self` constness and inherited optional virtual forwarding
- cached String/StringName default literal handling
- compile-time default options are inlined (primitives, enums, bitfields,
  Color/Vector/Rect); runtime-owned defaults stay optional
- Variant `asObject` / `asCallable` / `asInt` via pointer casts
- codegen varargs convert library-supplied codegen Variants to binding Variants;
  bindgen assembles the final engine pointer array
- host-targeted generator/translate-c with target-configured translated interface
  module; non-Windows installs skip PDB installation
- shared `src/godot/naming.zig` policy for generator output and reflection;
  generated classes/builtins expose `GodotClassName` for exact StringName lookup
- Zig `bitpack struct` emission with target-aware interface bitfield padding

## Validation

Last full review performed:

- all 1,069 generated classes compiled with the real hand-written builtin
  aggregate
- generated builtins and utility wrappers compiled
- bindgen bindings built
- `zig build`, `zig build test-generator`, and `zig build gen` pass

Temporary compile-check steps and files are removed after use.

## Known gaps

### Unsupported vararg return types

Generation now fails explicitly with `UnsupportedVarargReturn` instead of
emitting a bad fallback. If a future vararg return type should be supported,
add an explicit conversion.

### Non-bitfield enum ABI

Normal enum ptrcall slots are `i64`. Bitfields use their actual `u32`/`u64`
backing width. Revisit only if Godot defines a different enum ptrcall width.

### Hand-written builtins

Hand-written builtin implementations own their `toBinding` / `fromBinding`
methods and must expose any builtin enums used by generated class signatures.
Generated code assumes the hand-written aggregate exports the builtin types that
the API uses.

### Variant subclass downcast

No automatic class downcast is generated for Variant results. Callers use:

```zig
const object = variant.asObject();
const node: *Node = @ptrCast(object);
```

### Builtins aggregate

`builtins/builtins.zig` is hand-written and intentionally not generated. It
currently exports generated packed-array implementations.

### Overlays

Constants/enums/native/singletons overlays warn and are ignored. Revisit when a
real use case appears. Utility templates are intentionally unsupported.

### Registration

Codegen does not emit class registration metadata or callback casting. That
remains library-layer work.
