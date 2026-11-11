# Generator

One host-side executable with two backends:

```text
generator bindgen ...   -> raw bindings
generator codegen ...   -> automatic-dispatch layer
```

`main.zig` only parses the subcommand and dispatches. Shared semantic code lives
in `model/`; bindgen and codegen renderers stay separate.

## Source layout

```text
generator/
  main.zig
  tests.zig
  model/
    api_options.zig
    builtin_names.zig
    cli.zig
    defaults.zig
    docs.zig
    enum_emit.zig
    enum_utils.zig
    ExtensionApiJson.zig
    InterfaceJson.zig
    names.zig
    resolver.zig
    result_init.zig
    types.zig
  bindgen/
    custom/
    ...
  codegen/
    custom/
    ...
  docs/
    abi.md
    bindgen.md
    codegen.md
    status.md
```

The two customization trees are data consumed by the tool, not compiled source:

```text
generator/bindgen/custom/
generator/codegen/custom/
```

## Build integration

`build/generator.zig` owns:

- `buildGenerator`
- `runBindgen`
- `runCodegen`
- `runAll`
- `buildAndRunTests`

The run helpers return their starting `*std.Build.Step.Run`; they do not take or
mutate top-level steps. `runAll` creates the bindgen and codegen runs, makes
codegen depend on bindgen, and returns the codegen run. The top-level `build.zig`
steps depend on the returned runs.

Generator run steps use inherited stdio so successful diagnostics on stderr do
not become build failures; only a non-zero exit code fails the step.

Root steps:

```text
zig build gen
zig build bindgen
zig build codegen
zig build test-generator
```

`gen` runs bindgen first, then codegen. `bindgen` and `codegen` remain
independent standalone steps. `test-generator` runs the generator unit tests.

Default outputs:

```text
src/godot/bindings
src/godot
```

## Non-negotiable boundaries

- Codegen never overwrites `src/godot/bindings` or hand-written builtins.
- Codegen never generates `builtins/builtins.zig` for now.
- No codegen-owned `auto.zig`.
- No codegen-owned registration layer.
- Bindgen and codegen emitters do not merge.
- Generated output is deterministic; no timestamps.
- Actual Zig value -> Variant conversion for varargs is a library/caller concern.
  The library utility returns a tuple/array of codegen Variants; generated codegen
  wrappers convert each with `toBinding` into the binding Variant stack array.
  Bindgen then assembles the final engine pointer array.

## Start here

1. [abi.md](docs/abi.md) — primitive, pointer/value, result, enum, default rules.
2. [bindgen.md](docs/bindgen.md) — raw binding generation.
3. [codegen.md](docs/codegen.md) — classes, generated builtins, utility, overlays.
4. [status.md](docs/status.md) — implemented state and remaining gaps.

## Validation

```powershell
$env:ZIG_LIB_DIR=''
zig build
zig build test-generator
zig build bindgen
zig build codegen
zig build gen
zig fmt --check generator build.zig build/generator.zig
```
