# Godot 4 GDExtension template in Zig

This repository is a **clone-first template**, not a package and not a
framework. Copy or fork it into your Godot project and edit `build.zig`, the
generator, and the hand-written runtime in place. It is not consumed with
`zig fetch`; the project owns its entire source tree.

You keep control of the layers:

| Layer | Location | Keep it if you want |
|---|---|---|
| generated raw bindings | `src/godot/bindings/` except `bindings.zig` | ABI wrappers only |
| codegen | `src/godot/classes/`, `src/godot/builtins/generated/`, `src/godot/utility/`, and the generated root modules | automatic dispatch and typed classes |
| hand-written runtime | `src/godot/` files outside the generated subtrees | `Registry`, annotations, lifecycle, ownership, typed container wrappers, and the internal conversion layer behind the declared-type surfaces |
| generator | `generator/`, `build/generator.zig`, `gd_interface/` | regenerating for another Godot version |

A project can keep the full stack, use the runtime without `Registry`, or use
only the raw bindings. See [docs/bindings-only.md](docs/bindings-only.md).

The repository seed name is `test-zig`; the example export is `test_zig_init`.
These are starting values, not stable API names.

## Requirements

- a Zig version satisfying `minimum_zig_version` in `build.zig.zon`
- Godot 4.7 or newer. The runtime ABI is developed and tested against 4.7;
  the bundled `extension_api.json` identifies itself as 4.8 beta2.
- initialized submodules: `git submodule update --init`
  (`vendor/casez` and `vendor/zlob`)
- a Godot 4.8 executable for the optional `test-godot-live` step, passed with
  `-Dgodot_bin` or PATH; the committed `godot-test/` project targets 4.8
- a Godot project that loads the built shared library through a
  `.gdextension` file

## After cloning: make it yours

Recommended layout: place this repository inside the Godot project, for
example `<godot-project>/zig/`, and keep the root `.gdignore` so Godot does not
import the Zig tree.

1. Rename the package in `build.zig.zon`:
   - change `.name = .test_zig` to your project name;
   - run `zig build` once, copy the suggested fingerprint from the error, and
     update `.fingerprint`.
   The name also becomes the default shared-library name.
2. Rename the export symbol in `src/entrypoint.zig` (`test_zig_init`) and use
   the same string as `.gdextension` `entry_symbol`.
3. Create the Godot extension descriptor in your project:
   ```ini
   [configuration]
   entry_symbol = "my_game_init"
   compatibility_minimum = "4.7"
   reloadable = true

   [libraries]
   windows.debug.x86_64 = "lib/my_game.dll"
   linux.debug.x86_64 = "lib/libmy_game.so"
   macos.debug = "lib/libmy_game.dylib"
   ```
   Add release and other platform feature tags as needed. `reloadable = true`
   enables hot reload in editor builds; see
   [docs/registration.md](docs/registration.md#hot-reload).
4. Replace the example class scan wiring. `build.zig` scans `src/` and writes
   `src/example.gen.zig`; point both `generated_module_path` and the
   `@import("example.gen.zig")` in `src/entrypoint.zig` at your own module.
   Delete `src/example/` when you no longer need the examples.
5. Choose the install location. The default `-Dinstall_dir=../../lib` is
   relative to the install prefix (`zig-out`), so a repository at
   `<godot-project>/zig/` installs into `<godot-project>/lib/`. Change
   `install_dir` or the `.gdextension` library paths to match your layout.
6. Remove or keep layers deliberately. The runtime facade is convenient, but
   not required; see [docs/bindings-only.md](docs/bindings-only.md).

## First build

```powershell
git submodule update --init
zig build gen
zig build
zig build test
```

Generated bindings and codegen output are not committed. `zig build gen` runs
bindgen, codegen, and the example class-file scan. `zig build` requires that
generation step on a fresh checkout; it does not regenerate implicitly.
`zig build test` is the normal project test step and a wrapper over `test-godot`.
`zig build test-godot` runs all bindings/godot layer tests: it regenerates
bindings/codegen, then builds and runs the hand-written test root
`src/godot/tests/all.zig` and analyzes the generated modules.
`zig build test-generator` runs the host-side generator tests separately.
`zig build test-godot-live -Dgodot_bin=/path/to/godot` is an optional live
smoke test: it builds a separate dynamic library from `src/godot/tests/live/`,
installs it into the ignored `godot-test/lib/`, seeds the ignored Godot
extension-list cache, and runs the committed `godot-test/` project with
`--headless`. It uses `-Dgodot_bin` when provided, otherwise searches PATH,
runs only on the host target, and is not part of `test` or `test-godot`; the
normal test flow needs no Godot executable.

Cross-target test binaries are compiled and semantically analyzed; they run
only when the host can execute them. The builtin layout defaults from the target
pointer width (`float_32` for 32-bit, `float_64` otherwise); override it with
`-Dgdext_builtin_build_conf=...`.

## Project layout

```text
src/entrypoint.zig        example entry point; replace with your extension
src/example/              example extension classes (scaffold)
src/example.gen.zig       generated example class namespace (ignored)
src/godot/                hand-written runtime plus generated subtrees
  godot.zig               public facade imported as `godot`
  runtime.zig             process-wide dispatcher/registry state and lifecycle
  ownership.zig           Ref/Owned handles for engine objects, retain/release primitives, typed-construct ownership
  collections.zig         typed owning Array/Dictionary views over the builtins
  bindings/               bindgen output + hand-written bindings.zig entry
  classes/                codegen class output
  builtins/               hand-written builtins + generated builtins
  reflect/                type, hierarchy, and object helpers
  annotations/            opt-in markers
  registration/           optional Registry and lifecycle helpers
  tests/                  hand-written tests; all.zig is the test root
    live/                 separate dynamic-library tree for test-godot-live; not in all.zig
      entrypoint.zig      entry symbol; registers fixture classes
      live_node.zig       registration/annotation fixture class
      live_methods.zig    engine-method fixture class for both call paths
      live_owned_node.zig Owned-handle construction fixture class
      live_typed_node.zig typed-container and Ref-property fixture class
      live_resource.zig   object element fixture class
build/                    build helpers and optional class-file scanner
build/godot.zig           reusable Godot run helper
build/generator.zig       bindgen/codegen build wiring
generator/                host-side bindgen/codegen generator
gd_interface/             GDExtension header and JSON inputs
godot-test/               committed minimal Godot 4.8 project for test-godot-live
  project.godot           test project settings
  run_tests.gd            headless SceneTree runner; process exit code is the result
  tests/                  GDScript suites; test_case.gd plus domain scripts
  test_extension.gdextension  checked-in descriptor (entry_symbol test_extension_init)
  lib/                    gitignored; receives the built test extension and PDB
docs/                     design and build documentation
vendor/                   submodule dependencies
```

`docs/architecture.md` owns the dependency direction and ownership rules.
[docs/build.md](docs/build.md) owns the build steps, options, generated-output
layout, and the planned project-generation contract.

## Build options

The full table lives in [docs/build.md](docs/build.md). The commonly edited
options are:

| Option | Purpose |
|---|---|
| `-Dinstall_dir=...` | library install directory, relative to the install prefix |
| `-Dminimum_initialization_level=...` | `core`, `servers`, `scene`, or `editor` |
| `-Dgdext_bindgen_output_dir=...` | bindgen layer root |
| `-Dgdext_codegen_output_dir=...` | runtime/codegen layer root |
| `-Dgdext_interface_header=...`, `-Dgdext_interface_json=...`, `-Dgdext_extension_api_json=...` | Godot version inputs |
| `-Dgdext_builtin_build_conf=float_32|float_64` | builtin layout configuration |
| `-Dgdext_interface_import=...` | module name for the translated interface |
| `-Dgdext_member_init=...`, `-Dgdext_strip_deprecation=...` | generated extern struct and deprecation policy |

The optional live test takes its own option, `-Dgodot_bin=/path/to/godot`; see
[docs/build.md](docs/build.md#live-godot-tests).

The layer-root options move the whole layer, not just generated files. Generated
imports are relative to the runtime layer, and the hand-written `bindings.zig`
lives inside the bindgen root.

## Using only raw bindings

The raw ABI layer has no dependency on `godot.zig` or `runtime.zig`. The default
`build.zig` has a commented-out `bindings` module import for the entrypoint; add
or uncomment it, replace the helpful facade import, and call generated wrappers
with your own dispatcher. See
[docs/bindings-only.md](docs/bindings-only.md) for a minimal entry point and
the caveats around dispatcher initialization and allocators.

## Godot versions

The inputs in `gd_interface/` are ordinary files, not a hidden package:

```text
gd_interface/gdextension_interface.h
gd_interface/gdextension_interface.json
gd_interface/extension_api.json
```

Replace all three from the same Godot version, then run `zig build gen`,
`zig build test-generator`, and `zig build test-godot`. If you keep the live
harness, also run `zig build test-godot-live -Dgodot_bin=/path/to/godot` on the
host. Generated output is not deleted automatically; when upgrading, remove
generated trees first while preserving the hand-written `bindings.zig` and
builtin files, then regenerate.
Update `.gdextension` `compatibility_minimum` and the entrypoint version check
with the version you actually ship.

The bundled API JSON is 4.8 beta2 data, while the runtime ABI is tested against
4.7+. APIs added in 4.8 are not automatically available on a 4.7 runtime; use
4.8 inputs only after deciding to require 4.8.

## Template generation (planned)

There is no `zig build template` step yet. The intended contract is documented
in [docs/build.md](docs/build.md): copy a working tree after `zig build gen`,
copy the vendored dependencies and durable layer trees, rewrite the package
name/fingerprint, entry symbol, `.gdextension`, install path, and scan wiring,
then remove the example scaffold. Do not assume that step exists when following
this README.

## Class-file scanning

The example project uses the optional scanner:

- `zig build scan` scans for files containing `pub const Extends =`;
- `zig build gen` runs the same scan with the example configuration;
- the scanner writes a namespace module whose aliases are file stems, for
  example `pub const test_node2 = @import("example/test_node2.zig");`;
- a file-root class's engine name is that stem, so two files with the same stem
  collide at runtime. Give one `pub const GodotClassName = "OtherName";`;
- `ClassOptions.depth` (default 2) controls how many nested namespace levels
  `Registry.addClasses` expands.

The scanner is example wiring in `build.zig`, not a required layer. It ignores
`godot/**` because generated codegen classes also contain `pub const Extends =`;
if you move the runtime layer, update both the scan root and ignores. Generated
modules are build artifacts; they are ignored and must not be edited.

## Known limitations

- The hand-written tests under `src/godot/tests/` are Zig unit/build-analysis
  tests; `src/godot/tests/live/` is a separate dynamic-library tree, not a unit
  test. `zig build test` does not run the extension in a Godot engine. The
  optional `test-godot-live` step loads it headlessly and checks registration
  metadata, engine-method calls through both call paths, wrapper-typed container
  properties with their hint metadata and engine-side typing, signal emit
  delivery, and the `Owned` deinit/take paths; inspector rendering, hot reload,
  and other editor-only behavior still need an editor run.
- Static ClassDB properties, abstract classes (`is_abstract`), and callables are
  not implemented yet. Extension methods are registered and callable from
  GDScript (`Methods`/`Method` in [docs/classdb.md](docs/classdb.md)); method
  arguments are borrow-only (owning wrappers and owned-engine converters are
  compile errors as arguments), and an owned `RefCounted`
  result is declared as `godot.ownership.Ref(T)`. The next surface is
  `is_abstract`, followed by callables. Virtual signatures use engine-defined
  types, so a converter cannot appear there.
- Extension-to-extension class inheritance is rejected for registered classes.
- A failed `InitCallback` releases only framework-initialized values: fields
  with a custom `.init` initializer and `.deinit = .best_effort` get best-effort
  cleanup, while custom `.deinit` hooks, fields without a custom initializer,
  and values init code created itself are not touched. The framework never walks
  undefined fields; init code owns its failure cleanup, and `.init` values on
  custom-hook fields remain a known leak. See
  [docs/registration.md](docs/registration.md#instance-lifecycle).
- Generated output is configuration-specific. Keep one generated tree per
  target pointer width/precision or regenerate when switching.

## Documentation

Full index: [docs/README.md](docs/README.md). Project map and decisions:
[CONTEXT.md](CONTEXT.md). The declared-type conversion model, including custom
types with `Conversion` markers, is in [docs/conversion.md](docs/conversion.md);
that conversion layer is internal, not user API. Variant borrowed views, ownership,
and conversion are in [docs/variants.md](docs/variants.md). Engine object ownership
(`Ref` shares a reference, `Owned` exclusively destroys an unparented object, raw
pointers are borrowed) is in [docs/ownership.md](docs/ownership.md); typed
container wrappers and wrapper-typed properties are in
[docs/collections.md](docs/collections.md). Generator internals:
[generator/CONTEXT.md](generator/CONTEXT.md).
