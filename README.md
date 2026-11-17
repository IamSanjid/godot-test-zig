# test-zig

A template Godot 4 GDExtension project in Zig. It combines generated
GDExtension bindings and dispatch wrappers with a small hand-written runtime
layer.

The template keeps policy out of the library: generation and hand-written
runtime stay separate, annotations are opt-in, `Registry` is an optional
convenience collector, and no allocation, pooling, or instance-creation strategy
is forced.

## Requirements

- a Zig version satisfying `minimum_zig_version` in `build.zig.zon`
- Godot 4.8 (the bundled interface/API JSON is 4.8 beta)
- initialized submodules: `git submodule update --init`
- the `vendor/casez` source used by the generator

## Quick start

```powershell
git submodule update --init
zig build gen
zig build
```

Generated bindings and codegen output are not committed, so `zig build` requires
`zig build gen` on a fresh checkout.

The example export function is `test_zig_init` in `src/entrypoint.zig`. Point the
extension's `.gdextension` entry symbol at it. `build.zig` installs the shared
library into `install_dir`; set `-Dinstall_dir=...` for your project layout.

## Source map

```text
src/entrypoint.zig        example consumer; replace with your extension
src/godot/                hand-written runtime layer
  godot.zig               public facade imported as `godot`
  runtime.zig             process-wide dispatcher/registry state and lifecycle
src/godot/bindings/       bindgen output (generated, not committed)
src/godot/classes/        codegen class output (generated)
src/godot/builtins/       hand-written and generated builtins
generator/                host-side bindgen/codegen generator
gd_interface/             GDExtension header and JSON inputs
docs/                     design overview
```

## Design overview

- Bindgen produces raw ABI wrappers with explicit `dispatcher` parameters.
- Codegen produces the automatic-dispatch layer, codegen-facing builtins, and
  virtual metadata; generated code imports `runtime.zig`, not the facade.
- `src/godot/runtime.zig` owns process-wide dispatcher/registry state and the
  engine lifecycle.
- `src/godot/abi.zig` contains canonical ptrcall slot/read/write helpers.
- `src/godot/reflect` contains type/inheritance helpers.
- `src/godot/annotations` contains opt-in markers.
- `src/godot/registration` contains optional class lifecycle and virtual
  registration.
- `src/godot/godot.zig` is the public facade; user code imports it as `godot`.

A registered class gets construction/free callbacks, notification dispatch, and
virtual overrides. Methods, properties, signals, and constants are not exposed
to GDScript yet.

See [CONTEXT.md](CONTEXT.md) and [docs/](docs/).
