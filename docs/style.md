# Style

Follow the official [Zig style guide](https://ziglang.org/documentation/master/#Style-Guide).
This page records the project-specific additions and the few established
exceptions. They apply to the durable runtime, generator, and build helpers;
game code in a copied project may follow or replace them. Generated files are
exempt.

## Names

- Functions and other callable values: `camelCase`.
- Types, type aliases, and callables whose return type is `type`: `TitleCase`.
- Everything else: `snake_case`.
- Zero-field structs used as namespaces: `snake_case`.
- Files: `TitleCase` for files whose implicit struct has top-level fields
  (for example `Registry.zig`); `snake_case` otherwise. Directories are
  `snake_case`.
- Do not add type names using catch-all words such as `Value`, `Data`,
  `Context`, `Manager`, `State`, `utils`, `misc`, or initials.
- Do not use underscore prefixes to fake privacy or metadata. Name fields by
  semantics and document invariants.

Established exceptions:

- Engine names and Godot ABI parameter names are kept as-is (`p_instance`,
  `_ready`, `_process`, generated engine class names such as
  `TextServerManager`).
- Lifecycle callback builders keep their engine callback names:
  `CreateInstance`, `RecreateInstance`, and `FreeInstance` are named after the
  GDExtension callbacks they build. They are functions, not types or callables
  returning a type, so the exception is deliberate; do not rename them to
  `camelCase`.
- Generated bindings own their identifiers, including ABI padding fields
  (`_pad0`) and opaque payload fields (`_opaque`).
- `Variant.Data` is the engine payload layout, not a catch-all data type.
  Generator JSON unions named `Data` mirror their input schema.
- Scanner-generated namespace modules (`*.gen.zig`) own their file-stem alias
  names and header; if the optional scanner is kept, run `zig build scan`
  instead of editing them.

## Comments

Write comments the way the Zig standard library does: normally short, never
narrating code, and as long as the contract requires. There is no line quota.

- `//!` module docs explain what the module is and the invariant or context a
  caller needs. Most are one to three lines. Longer is correct when the module
  implements a nontrivial algorithm or owns a subtle lifetime/ABI contract; see
  `std/debug/Dwarf/SelfUnwinder.zig`.
- `///` declaration docs lead with a self-contained sentence. They may be one
  line or several paragraphs when documenting an algorithm, security property,
  wire format, ownership rule, or error behavior; see `std/Io/Writer.zig`
  (`print`) and `std/testing.zig` (allocation-failure checks). Do not pad a
  simple declaration with prose it does not need.
- Document only what the declaration cannot show: contracts, ownership, error
  behavior and side effects, preconditions, invariants, safety, performance, and
  deliberate oddities. Name and signature already cover the rest.
- Do not document trivial `init`/`deinit`/`get`/`set`, well-named fields, or
  well-named parameters. Private fields may be documented when their invariant
  is non-obvious, as stdlib does for `ArrayLists.items`/`capacity` or
  `SelfUnwinder.pc`.
- Source comments and `docs/` must not repeat each other. Source owns the
  per-declaration contract; `docs/` owns cross-module design, lifecycle order,
  option tables, and rationale. Link instead of copying.
- Examples are rare. Use one when the call shape or format is otherwise unclear;
  complex reference documentation may legitimately use longer examples.
- Implementation comments explain why: an invariant, engine contract,
  workaround, or warning. One line is common, not mandatory.
- Avoid banner separators and commented-out code. Compile-only coverage gets one
  line: `// Compile-only coverage; analyzed on every build.`
- Headings and field-by-field sections inside doc comments are exceptional;
  prefer prose. Reserve them for reference material with genuinely independent
  subsections.

The test is necessity, not brevity: delete comments that restate code, and keep
comments that prevent a future reader from making a wrong assumption.

## Imports

Imports belong at the bottom of the file, after declarations, in this order:

1. Standard library modules (`std`, `builtin`) and aliases derived from them.
2. Third-party modules: every import whose path does not end in `.zig`
   (`bindings`, `build_options`, `naming`, `casez`, `godot`) and aliases derived
   from them.
3. Local `.zig` modules, in this order: parent-directory paths (`../...`), then
   same-directory paths (`init.zig`, `./...`). Aliases derived from an import
   follow it immediately.
4. Public dependency re-exports that belong to the import block (not a facade's
   public API block), such as `runtime.zig`'s `DefaultDispatcher`,
   `engine_allocator`, `is_wasm`, and `reflect` aliases. Put them after the
   private imports, with no blank lines inside and ASCII-sorted by declaration
   name. Public API declarations and facade re-export blocks stay in the public
   API block.

Separate the four groups with one blank line. Do not put blank lines inside a
group, including between parent and local module imports.

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;
const build_options = @import("build_options");
const naming = @import("naming");

const builtins = @import("../builtins/builtins.zig");
const registration = @import("../registration/registration.zig");
const constants = @import("constants.zig");
const marker_kind = @import("marker.zig");
```

`@import("builtin")` stays with the standard modules. Public re-exports such as
`pub const marker = @import("marker.zig");` stay in the public API block; they
are part of the module's exported surface, not private import aliases.

Only aggregator/facade modules group an import with its public re-exports:

```zig
const on_ready = @import("on_ready.zig");
pub const OnReady = on_ready.OnReady;
pub const initOnReadyFields = on_ready.initOnReadyFields;
pub const findOnReadyFieldNames = on_ready.findOnReadyFieldNames;
```

One blank line separates source-module groups, and there are no blank lines
inside a group. A directly re-exported submodule starts its own group with
`pub const name = @import("name.zig");`. Imports that are not used for a
re-export group (std, third-party, or unrelated parent modules) stay at the
bottom under the normal import rules.

## Comptime access

- Use direct access for statically known declarations and fields:
  `Marker.Engine`, `info.marker.toEngine`, `spec.engine`.
- `@hasDecl` is a guard for optional declarations; `@field` is only for names
  computed at comptime, such as loops over `decl_names` or user-provided
  strings.
- Use `reflect` helpers instead of open-coding `@typeInfo` switches when the
  helper already exists.

## Public facade vs internal modules

`godot.zig` is the user API surface. Export the modules and declarations user
code is meant to call (`annotations`, `ownership`, `collections`, `abi`,
`registration`, codegen types, runtime entry points). Implementation modules stay
internal: `conversion.zig`, `ptrcall.zig`, caches, and the property/registration
helpers behind a surface are imported by the runtime, not re-exported by the
facade.

- Put a rule in the layer that owns it instead of exposing it from a surface or
  duplicating it in one. Declared-type support and value conversion belong to the
  internal conversion layer; canonical ABI layout to `abi.zig`; object-slot
  reference rules to `ptrcall.zig`.
- Delivered docs describe user-facing surfaces and the conversion model; they do
  not present internal functions, caches, or private primitives as API. Use a
  concept name ("the conversion layer", "the Variant path", "the ptrcall path")
  and link the owning page.
- Tests may reach internals through the test-only `godot.internal` hook, which is
  an empty struct outside test builds. It is not API: do not use it from user
  code and do not document it as a supported path.

## Tests

- Tests mirror the module layout under `src/godot/tests/`. `all.zig` is the
  root; `zig build test-godot` builds and runs it, and it imports every test
  file.
- `src/godot/tests/live/` is a separate dynamic-library source tree for the
  optional `zig build test-godot-live` step; `all.zig` does not import it.
  `entrypoint.zig` only exports the entry symbol and registers fixture classes;
  each fixture class lives in its own sibling `.zig` file. Its Godot project,
  `SceneTree` runner, and GDScript suites live under `godot-test/`; suites
  extend `godot-test/tests/test_case.gd` and are listed explicitly in
  `run_tests.gd`.
- Adding a live test means: add the fixture class file, register it in
  `entrypoint.zig`, add a GDScript suite under `godot-test/tests/`, and add that
  suite to `SUITES`. Removing it means removing those four references; never
  add live fixtures to `all.zig`.
- Implementation modules stay test-free: no `test "..."` blocks, coverage
  fixtures, or `comptimeSelfCheck` under `src/godot/` outside `tests/`. Tests
  own those checks.
- Unit tests import the runtime through the public `godot` facade, not relative
  parent paths. Internal-module coverage uses the test-only `godot.internal`
  hook; generated-layer analysis may also use the `bindings` module.
- Test files are hand-written and committed. Generated output is ignored and is
  never edited to make a test pass.

## Formatting

- Four-space indentation.
- Opening braces on the same line unless wrapping requires otherwise.
- Lists longer than two entries go one item per line with a trailing comma.
- Aim for 100 columns; use common sense for diagnostics and generated code.
- Run `zig fmt` on hand-written files.
