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
| `zig build test-godot` | test binary | All bindings/godot layer tests: regenerates first, then builds and runs `src/godot/tests/all.zig` and analyzes generated modules. |
| `zig build test-godot-live` | `godot-test/lib` | Optional live smoke test. Uses `-Dgodot_bin` or searches PATH, requires the host target, builds a separate dynamic library, copies it into the ignored `godot-test/lib/`, then runs `godot-test/` headlessly. Not part of `test`. |
| `zig build test` | test binary | Normal project test step: wrapper over `test-godot`; runs the runtime/layer tests, not the generator suite or the live tests. |

## Tests

Hand-written unit tests are committed source, not generated output. They live
under `src/godot/tests/`, mirror the module layout, and import the runtime
through the public `godot` facade. `src/godot/tests/all.zig` is the test root:
it imports every test file, and `zig build test-godot` regenerates first, then
builds and runs it. `src/godot/tests/classes.zig` adds the semantic analysis of
the generated bindings/codegen. Implementation modules carry no `test` blocks.

`zig build test` is a wrapper over `test-godot` and runs the normal runtime/layer
test root. `test-generator` is the template-only generator suite; `test-godot`
is the explicit layer-test step. `test-godot-live` is a separate, optional
engine-facing smoke test: `test`, `test-godot`, and `test-generator` never
depend on it and need no Godot executable. The test root path is fixed in
`build.zig`; if the runtime layer moves, move the test tree with it and update
that path.

### Live Godot tests

`zig build test-godot-live -Dgodot_bin=/path/to/godot` loads the extension into
a real Godot process. It is separate from the unit suites and is not part of
`test` or `test-godot`.

- `-Dgodot_bin` is optional. When omitted, `addRun` searches PATH for
  `godot`/`godot4`; if none is found, the step fails with a diagnostic instead
  of panicking.
- The step is host-only: `-Dtarget` must match the build host's OS and CPU
  architecture because the built library is loaded by a local Godot process. A
  cross-target request fails with a diagnostic.
- It builds a dynamic library named `test_extension` from
  `src/godot/tests/live/entrypoint.zig`. That file only exports the entry symbol
  and registers fixture classes; `live_node.zig`, `live_owned_node.zig`,
  `live_typed_node.zig`, and `live_resource.zig` hold the fixture classes. The
  directory is a separate dynamic-library source tree and is not imported by
  `src/godot/tests/all.zig`.
- The build installs the library into the gitignored `godot-test/lib/` (plus the
  PDB on Windows) using an artifact install override. The destination is
  relative to the default install prefix (`zig-out`), so run this step with the
  default `--prefix`; it does not rewrite checked-in project files.
- It then runs:

  ```console
  godot --headless --path godot-test --script res://run_tests.gd
  ```

- `godot-test/` is a committed minimal Godot 4.8 project: `project.godot`,
  `run_tests.gd`, the `tests/` suite tree, and a checked-in
  `test_extension.gdextension` with `entry_symbol = "test_extension_init"` and
  `lib/...` paths. Use a matching Godot 4.8 executable (verified with
  `4.8.beta2`). `godot-test/.godot/` and `godot-test/lib/` are gitignored.
- Non-editor Godot discovers GDExtensions only through
  `godot-test/.godot/extension_list.cfg`; `--script` does not scan the project.
  The step seeds that ignored file, so a fresh checkout works without opening
  the editor once.
- `run_tests.gd` extends `SceneTree` and only loads the suites listed in its
  `SUITES` array, prints each failure as `LIVE TEST FAILED [suite]: message`,
  and sets the exit code. Suites extend `tests/test_case.gd` and live directly
  under `tests/`; add a new suite by adding its script to `SUITES`.
- The live extension registers four fixture classes. `LiveNode` (extends
  `Node`) has properties `health` (range hint `0,100`), `label` (String, initial
  `"live"`), and `mode` (enum hint; `Mode { idle, running = 3 }`), group `Live`,
  signals `pinged(health: int)` and `signaled(text, numbers, payload, transform,
  count)`, and integer constants `MAX_HEALTH = 100` and the
  `Mode` enum (`IDLE`, `RUNNING = 3`). `LiveTypedNode` (extends `Node`) has
  wrapper-typed container properties `numbers` (`godot.collections.Array(i32)`),
  `resources` (`Array(?*LiveResource)`), and `scores`
  (`Dictionary(String, i32)`); its creation callback fills the wrappers and
  moves them into the fields, and its deinit callback runs the property cleanup.
  The container hints derive automatically from each wrapper's
  `Element`/`Key`/`Value` declarations. It also has owned
  `godot.ownership.Ref(Resource)` properties `resource` (moved from
  `Resource.construct()`) and `resource_copy` (moved from a generated
  `Resource.duplicate` return). `LiveOwnedNode` (extends `Node`) exercises the
  manual `godot.ownership.Owned(Node)` handle: `onInit` destroys one
  unparented constructed node with `Owned.deinit()` and hands another to itself
  with `Owned.take()` as a child. `LiveResource` (extends `Resource`) is the
  object element class and has one exported scalar property.
- The GDScript suites check class existence, instantiate/free, property list
  metadata, signal metadata and delivery, constants, default/set/get values, the
  auto-derived container hint strings, engine-side container typing, container
  and `Ref` property set/get round-trips, and the `Owned` deinit/take outcomes.

The step covers headless registration, property/signal/constant metadata,
signal emit delivery, wrapper-typed container and owned-`Ref` property hints,
typing, and round-trips, and the `Owned` manual-ownership paths. It does not
cover inspector rendering, hot reload, virtual callbacks, or gameplay paths;
those still need a manual engine or editor run. Like `zig build`, it consumes
generated sources and does not regenerate them; run `zig build gen` first on a
fresh checkout.

## Reusing `build/godot.zig`

`build/godot.zig` owns only the reusable Godot launch step. The extension
library remains an ordinary `b.addLibrary(...)` call: there is no wrapper,
because forwarding `name`/`root_source_file`/`imports`/`target`/`optimize` and
setting `.linkage = .dynamic` adds no policy and hides the standard build API.

`addRun` accepts `godot_bin` (optional; PATH is searched when omitted),
`project_path`, `headless`, `editor`, `script`, `cwd`, and `extra_args`, and
returns `*std.Build.Step`: a process step, or a fail step when no executable is
found.

```zig
const godot_build = @import("build/godot.zig");

const lib = b.addLibrary(.{
    .name = "my_extension",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/entrypoint.zig"),
        .imports = &.{.{ .name = "godot", .module = godot }},
        .target = target,
        .optimize = optimize,
    }),
    .linkage = .dynamic,
});

const run = godot_build.addRun(b, .{
    .godot_bin = godot_bin,
    .project_path = ".",
    .headless = true,
    .script = "res://tests/run.gd",
    // Export example: .extra_args = &.{ "--export-release", "Linux/X11", "build/game.x86_64" },
});
```

Attach the run step to any `b.step(...)`; `headless = false` launches the
project normally, and `editor = true` opens the project in the editor. The
helper does not yet model export subcommands, but `extra_args` passes them
through unchanged. `test-godot-live` is just one caller of this helper.

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
| `-Dgdext_codegen_output_dir` | `src/godot` | Runtime/codegen layer root; must contain `runtime.zig`, `godot.zig`, and `naming.zig`. Generated code imports hand-written files at fixed relative depths; hand-written tests are separate under `src/godot/tests/`. |
| `-Dgdext_interface_import` | `godot_interface` | Module name generated bindings use for the translated interface. |
| `-Dgdext_member_init` | `zero` | Initialization of generated extern struct members. |
| `-Dgdext_strip_deprecation` | `false` | Strip deprecated interface/API members from generated output. |
| `-Dgodot_bin` | PATH search | Godot executable used only by `test-godot-live`; when omitted, `addRun` searches PATH and fails the step if no executable is found. |

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
- `gdext_codegen_output_dir` is the parent of the hand-written runtime layer
  (`runtime.zig`, `godot.zig`, `naming.zig`, `abi.zig`, `ptrcall.zig`,
  `conversion.zig`, and the other hand-written modules), because generated
  imports are relative to that layout. It is not safe to copy only the generated
  subtrees without the hand-written layer beside them; the internal conversion
  and ptrcall modules are part of that durable layer.
- Hand-written tests are not part of either layer root; they are committed
  source under `src/godot/tests/`.

The repository `.gitignore` currently knows only the default paths. If a
project changes either layer root, update `.gitignore` (and the example scan
ignores) to match. The example extension's `.gdextension` and Godot project
files live outside this repository; the committed `godot-test/` project is a
test fixture, not your game project. Keep library paths consistent with
`install_dir`.

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

If you keep the live harness, finish with
`zig build test-godot-live -Dgodot_bin=/path/to/godot` on the host.

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
