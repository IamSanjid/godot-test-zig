# Codegen backend

Codegen emits the automatic-dispatch layer. It supplies `runtime.dispatcher()`
and converts between codegen-facing types and binding types.

`--out-dir` / `--output-dir` is required. `--out-dir` is the canonical spelling.
There is no fixed output path.

## Output

```text
<out_dir>/
  classes/
    classes.zig
    <api_type>/<api_type>.zig
    <api_type>/<snake>.zig
  utility/
    utility.zig
    <category>.zig
  builtins/generated/<snake>.zig
  constants.zig
  enums.zig
  native.zig
  singletons.zig
```

Codegen does not generate `builtins/builtins.zig` and does not write
`godot.zig`.

## Import contract

- bindings are imported through a module named `bindings` by default
  (`--bindings-module` can rename it).
- the runtime is a **file** at `<out_dir>/godot.zig`, imported relatively:
  - classes with an api type: `../../godot.zig`
  - classes without: `../godot.zig`
  - utility: `../godot.zig`
  - generated builtins: `../../godot.zig`
  - singletons: `godot.zig`
- builtins always come through the hand-written aggregate:
  - classes: `../../builtins/builtins.zig`
  - utility: `../builtins/builtins.zig`
  - generated builtins: `../builtins.zig`

## Classes

Each class is a codegen-owned `opaque` type with:

- `Extends` pointing at the codegen base class or `void`
- class constants and enums as binding aliases
- `construct()` for instantiable non-singletons
- `Virtual.Required` / `Virtual.Optional` codegen-typed callbacks
- required virtuals metadata only; optional wrappers forward to bindings
- codegen-typed signals with `connect` / `disconnect` / `isConnected`
- a `Properties` namespace with codegen `Type`, getter, setter and index
- methods and options structs

Methods:

- implicit `runtime.dispatcher()`
- class self is `@ptrCast(self)` at the binding boundary
- class pointer args use `@ptrCast`
- builtins use `toBinding` / `fromBinding`
- enums and native types are already aliases
- optional arguments use a generated options struct with field-wise
  `toBinding()`
- varargs accept a tuple/array of codegen Variants from the library utility and
  convert each with `toBinding` into a binding Variant stack array

Inherited methods and optional virtuals are forwarded through the binding class
so parent virtual behavior remains reachable.

## Generated builtins

One file is generated for every non-primitive `builtin_classes` entry:

```text
<out_dir>/builtins/generated/<snake>.zig
```

They contain:

- `extern struct` layout using the selected build configuration
- size/offset/alignment checks
- constructors, operators, methods and varargs
- custom-method support
- `toBinding` / `fromBinding` from
  `generator/codegen/custom/templates/builtins/conversions.zig.tpl`

No generated builtin file is produced for `Object` or `Variant`.

The hand-written aggregate decides which builtin implementation consumers see.
Generated builtins are a baseline/reference until promoted manually.

## Utility

`utility/<category>.zig` contains static wrappers:

```zig
pub inline fn sin(angle: f32) f32 {
    return bindings.utility.math.sin(runtime.dispatcher(), angle);
}
```

Class pointers use `@ptrCast`; builtin args/returns use `toBinding` /
`fromBinding`; enum/native values are direct. Varargs accept codegen Variants and
are converted to binding Variants before the binding call.

## Artifacts

- `constants.zig` — global constant values (literal values because the bindings
  aggregate does not currently expose `bindings.constants`)
- `enums.zig` — aliases to `bindings.enums`
- `native.zig` — aliases to `bindings.native`
- `singletons.zig` — cached singleton accessors using binding singleton helpers

## Custom overlays

Codegen custom data lives under:

```text
generator/codegen/custom/
  classes/<api_type>/<snake>.zig
  classes/<snake>.zig
  builtins/<snake>.zig
  utility/<category>.zig
  templates/classes/*.zig.tpl
  templates/builtins/*.zig.tpl
```

Class/builtin/utility overlays support:

```zig
// @imports
// @imports_end
// @replace methodName
// @replace_end methodName
// @method addedName
// @method_end addedName
```

Targets are generated Zig method/function names (camelCase). Custom files are
read, never created.

Templates support:

```zig
// @template replace methodName
// @template_end methodName
// @template method addedName
// @template_end addedName
```

Placeholders: `{{Class}}`, `{{Builtin}}`, `{{binding_class}}`,
`{{binding_builtin}}`, `{{api_type}}`, `{{dispatcher}}`, `{{method}}`.

Precedence:

1. per-artifact `@replace`
2. template replacement
3. generated method

Template additions are emitted after generated methods and before per-artifact
`@method` additions. Names must not collide.

## Unsupported overlays

These paths are intentionally not handled yet. If they exist, codegen warns and
ignores them:

```text
generator/codegen/custom/constants.zig
generator/codegen/custom/enums.zig
generator/codegen/custom/native.zig
generator/codegen/custom/singletons.zig
```

Utility templates are intentionally not supported.
