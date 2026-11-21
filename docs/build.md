# Build and template wiring

`build.zig` is project code, not an installed package entry point. This page
documents the intended contract for a cloned template and for the future
project-generation step.

## Design rules

- Generation is explicit. `zig build` consumes generated sources; it does not
  regenerate them.
- Generated output is replaceable. Keep it out of hand edits and out of the
  durable source layer.
- Layer roots are build options. Moving a layer means moving the whole layer,
  not only the generated files inside it.
- A template copy should be self-contained after `zig build gen`, including the
  vendored generator inputs and generated sources.

## Steps

| Step | Writes | Notes |
|---|---|---|
| `zig build` | `zig-out`, then `install_dir` | Requires `zig build gen` on a fresh checkout. |
| `zig build gen` | bindgen + codegen output + example class namespace | The normal source-generation step. |
| `zig build bindgen` | raw generated bindings | Uses `gdext_bindgen_output_dir`. |
| `zig build codegen` | codegen output | Depends on bindgen; uses `gdext_codegen_output_dir`. |
| `zig build scan` | example class namespace | Example scaffold; configured in `build.zig`. |
| `zig build test-generator` | generator test binary | Host-side generator tests. |
| `zig build test-godot` | test binary | Regenerates first, then unit-tests the runtime and analyzes generated modules. |
| `zig build test` | both test suites | Convenience umbrella. |

## Options

| Option | Default | Contract |
|---|---|---|
| `-Dtarget` | host | Godot library target. |
| `-Doptimize` | `Debug` | Zig optimize mode. |
| `-Dminimum_initialization_level` | `scene` | `core`, `servers`, `scene`, or `editor`. |
| `-Dinstall_dir` | `../../lib` | Relative to the install prefix (`zig-out`). The default assumes the repository sits one directory below the Godot project, so the library lands in `<project>/lib`. |
| `-Dgdext_interface_header` | `gd_interface/gdextension_interface.h` | GDExtension header input. |
| `-Dgdext_interface_json` | `gd_interface/gdextension_interface.json` | GDExtension interface JSON input. |
| `-Dgdext_extension_api_json` | `gd_interface/extension_api.json` | Godot extension API JSON input. |
| `-Dgdext_builtin_build_conf` | target pointer width | `float_32`/`float_64` layout configuration. Must match the engine precision. |
| `-Dgdext_bindgen_output_dir` | `src/godot/bindings` | Bindgen layer root; must contain the hand-written `bindings.zig` module root. |
| `-Dgdext_codegen_output_dir` | `src/godot` | Runtime/codegen layer root; must contain `runtime.zig`, `godot.zig`, `naming.zig`, and `tests.zig`. Generated code imports hand-written files at fixed relative depths. |
| `-Dgdext_interface_import` | `godot_interface` | Module name generated bindings use for the translated interface. |
| `-Dgdext_member_init` | `zero` | Initialization of generated extern struct members. |
| `-Dgdext_strip_deprecation` | `false` | Strip deprecated interface/API members from generated output. |

Changing a generation-affecting option requires `zig build gen` before the next
build. Generated output is per target pointer width and builtin precision; do
not reuse a generated tree across different configurations.

## Generated output and copying

The defaults are:

```text
src/godot/bindings/          generated raw ABI + hand-written bindings.zig
src/godot/classes/           generated class wrappers
src/godot/builtins/generated/
src/godot/utility/
src/godot/constants.zig
src/godot/enums.zig
src/godot/native.zig
src/godot/singletons.zig
src/example.gen.zig          generated example namespace (example scaffold)
```

There are two layer roots, not two arbitrary output folders:

- `gdext_bindgen_output_dir` owns the bindgen tree, including the hand-written
  `bindings.zig` module entry point. Moving that directory means moving the
  entry point too.
- `gdext_codegen_output_dir` is the parent of `runtime.zig`, `godot.zig`,
  `naming.zig`, and `tests.zig`, because generated imports are relative to that
  layout. It is not safe to copy only the generated subtrees without the
  hand-written layer beside them.

The repository `.gitignore` currently knows only the default paths. If a
project changes either layer root, update `.gitignore` (and the example scan
ignores) to match. The example `.gdextension` and Godot project files live
outside this repository; keep library paths consistent with `install_dir`.

### Generated-output policy for a template copy

A copied project should choose one policy and document it:

- keep generated output out of version control and run `zig build gen` as the
  first build step, or
- commit the generated output for one verified target/configuration and
  regenerate explicitly when upgrading Godot.

Do not mix configurations in one committed tree.

## Godot version updates

The generator inputs are intentionally ordinary files:

- `gd_interface/gdextension_interface.h`
- `gd_interface/gdextension_interface.json`
- `gd_interface/extension_api.json`

Replace all three from the same Godot version, then run:

```console
zig build gen
zig build test-generator
zig build test-godot
```

The generator writes output files but does not delete stale generated files.
When changing versions, remove the generated subtrees first while preserving
`src/godot/bindings/bindings.zig` and the hand-written builtin files, then
regenerate. Update the `.gdextension` `compatibility_minimum` and the entrypoint
version check together with the inputs you actually ship.

The bundled `extension_api.json` identifies itself as Godot `4.8.beta2`; the
runtime ABI is developed and tested against Godot 4.7+. Generated APIs with a
`since` newer than the runtime you target are not automatically portable.

## Project generation (planned)

There is no `zig build template` step yet. The intended contract is:

1. Start from a working tree after `zig build gen`, not a bare `git archive`;
   generated bindings/codegen must be present in the copy.
2. Copy the durable tree and vendored dependencies, not caches or build output.
3. Rewrite `build.zig.zon` name/fingerprint, entry symbol, `.gdextension`
   paths, `install_dir`, and the example scan wiring.
4. Remove the example scaffold: `src/example/`, `src/example.gen.zig`, the
   example `addClasses` block, and example-only build wiring.
5. Decide whether generated output is committed or regenerated, then rewrite
   `.gitignore` and `.gdignore` for the chosen layout.

Until that step exists, do these edits manually after cloning.
