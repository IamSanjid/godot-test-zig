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

Codegen does not generate `builtins/builtins.zig` and does not write the
hand-written runtime `runtime.zig` or the public facade `godot.zig`.

## Import contract

- bindings are imported through a module named `bindings` by default
  (`--bindings-module` can rename it).
- the runtime is the hand-written **file** at `<out_dir>/runtime.zig`, imported
  relatively:
  - classes with an api type: `../../runtime.zig`
  - classes without: `../runtime.zig`
  - utility: `../runtime.zig`
  - generated builtins: `../../runtime.zig`
  - singletons: `runtime.zig`
- builtins always come through the hand-written aggregate:
  - classes: `../../builtins/builtins.zig`
  - utility: `../builtins/builtins.zig`
  - generated builtins: `../builtins.zig`
- shared naming policy is available through the `naming` module; generated
  classes/builtins expose `GodotClassName`, used by `StringName.fromType`, while
  `StringName.fromUserType` keeps the user type name verbatim

## Classes

Each class is a codegen-owned `opaque` type with:

- `Extends` pointing at the codegen base class or `void`
- class constants and enums as binding aliases
- `construct()` for instantiable non-singletons
- `Virtual.Required` / `Virtual.Optional` codegen-typed callbacks, including
  inherited virtuals
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
- compile-time defaults (primitives, enums, bitfields, Color/Vector/Rect types)
  are non-optional option fields and are converted directly
- runtime-owned defaults stay optional and keep the `if (self.field) |value|`
  conversion path
- caller-provided option values are borrowed; only defaults constructed by the
  binding layer are deinitialized
- varargs accept a tuple/array of codegen Variants from the library utility and
  convert each with `toBinding` into a binding Variant stack array

Inherited methods and optional virtuals are forwarded through the binding class
so parent virtual behavior remains reachable.

## Generated builtins

One file is generated for every non-primitive `builtin_classes` entry:

```text
<out_dir>/builtins/generated/<snake>.zig
```

For generated types the file contains:

- `extern struct` layout using the selected build configuration
- size/offset/alignment checks
- constructors, operators, methods and varargs
- custom-method support
- `toBinding` / `fromBinding` from
  `generator/codegen/custom/templates/builtins/conversions.zig.tpl`

No generated builtin file is produced for `Object` or `Variant`.

### Hand-written builtins

The following builtins are implemented by hand under `src/godot/builtins/`:

```text
AABB Basis Color Plane Projection Quaternion Rect2 Rect2i RID
Transform2D Transform3D Vector2 Vector2i Vector3 Vector3i Vector4 Vector4i
```

For these, codegen emits **top-level functions only**. It does not emit:

```zig
pub const Vector2 = extern struct { ... };
```

Instead the generated file imports:

```zig
const builtins = @import("../builtins.zig");
```

and every builtin type reference is qualified, for example:

```zig
pub inline fn angle(self: *const builtins.Vector2) f32 {
    const result = bindings.builtins.Vector2.angle(
        @ptrCast(self),
        runtime.dispatcher(),
    );
    return result;
}
```

Templates, replacements and method additions still apply unchanged. Template
`{{Builtin}}` resolves to `builtins.<Name>` for these files. Layout checks and
the extern struct declaration are skipped because the hand-written type remains
the single declaration.

The hand-written aggregate still points at the hand-written implementation; the
generated file is a top-level function library, not an aggregate entry. This
keeps one authoritative type declaration while letting hand-written code import
the generated file as a function namespace and select wrappers from it.

The hand-written table lives in `generator/codegen/builtin.zig`. Update it when a
hand-written builtin is added or removed.

## Utility

`utility/<category>.zig` contains static wrappers:

```zig
pub inline fn sin(angle: f64) f64 {
    return bindings.utility.math.sin(runtime.dispatcher(), angle);
}
```

Class pointers use `@ptrCast`; builtin args/returns use `toBinding` /
`fromBinding`; enum/native values are direct. Varargs accept codegen Variants and
are converted to binding Variants before the binding call.

## Artifacts

- `constants.zig` - global constant values (literal values because the bindings
  aggregate does not currently expose `bindings.constants`)
- `enums.zig` - aliases to `bindings.enums`, so bindgen enum-body extensions
  (for example `PropertyUsageFlags.exported`) are inherited
- `native.zig` - aliases to `bindings.native`
- `singletons.zig` - cached singleton accessors using binding singleton helpers

## Function metadata

Every generated class, generated builtin struct, and top-level hand-written
builtin namespace gets:

```zig
pub const MemberFunctions = struct {
    pub const methodName = Owner.methodName;
};

pub const StaticFunctions = struct {
    pub const staticMethodName = Owner.staticMethodName;
};
```

These alias the actual generated functions rather than storing standalone
signature types, so reflection sees a real function value. A class `Virtual`
namespace includes its own virtuals and inherited virtuals; callback `self`
types are the derived class. How consumers use these metadata entries is a
library concern.

Rules:

- `MemberFunctions` contains non-static methods.
- `StaticFunctions` contains static methods.
- Class constructors (`construct`) and builtin constructors are excluded.
- Builtin destructors and operators are excluded.
- Class `Virtual` metadata includes inherited virtuals, with the child class as
  the callback self type; optional virtual wrappers are still ordinary generated
  member functions and are included in `MemberFunctions`.
- `Virtual.Meta` carries the engine hash, staticness, and the exact
  `godot_name` from `extension_api.json`, so runtime registration does not need
  to repeat a name conversion.
- Inherited methods appear in the derived class metadata because the wrappers
  exist on the derived class.
- Metadata is generated after API method emission, so custom/template
  replacements keep their metadata entry. Helper additions are not treated as
  Godot API methods.
- Zig-keyword method names are escaped in both the field and alias.

For hand-written builtins the metadata is top-level and aliases through the file
module:

```zig
const _self = @This();

pub const MemberFunctions = struct {
    pub const angle = _self.angle;
};
```

How hand-written code consumes the generated function namespace belongs to the
hand-written layer, not codegen.

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

Codegen custom files use the shared section grammar:

```zig
// @section file
// @section artifact name
// @section replace methodName
```

- `file` adds file-scope code.
- `artifact` appends a new member and collision-checks its name.
- `replace` replaces a generated method.

`extend` sections are bindgen-only and rejected by codegen. Codegen global,
class and builtin enum declarations are aliases of the binding enums, so
declarations that bindgen extends into an enum body flow through codegen
automatically; codegen has no separate enum body to insert into.

Templates use the same section grammar, with a file-level target directive.
Codegen supports both `replace` and `artifact`; bindgen supports `artifact`
plus class `replace` sections only.

```zig
// @templates_for Node:derived, Control, Button
// @section replace process
// @section_end replace process

// @section artifact helper
// @section_end artifact helper
```

- `@templates_for` is optional; omitted or `*` means every type.
- `Node` is exact; `Node:derived` also applies to descendants.
- `replace` targets generated Zig identifiers (`do_thing` -> `doThing`).
- `artifact` adds a member whose Zig identifier is the section name.
- Builtins cannot use `:derived` and must be generated, non-primitive types.
- Unknown targets and duplicate method names are errors.
- A missing replacement target is a no-op.
- A file's `@templates_for` applies to every block; split files for different
  targets.
- Use per-artifact custom overlays for a one-class replacement.

The `{{method}}` placeholder is the raw API name for replacements and the
declared name for additions. Placeholders: `{{Class}}`, `{{Builtin}}`,
`{{binding_class}}`, `{{binding_builtin}}`, `{{api_type}}`, `{{dispatcher}}`,
`{{method}}`.

Substitution is literal; the renderer does not add prefixes.

- `{{Builtin}}` is a bare `Name` for generated struct builtins.
- `{{Builtin}}` is already `builtins.Name` for hand-written top-level builtins.
- `{{binding_builtin}}` is always `builtins.Name`; templates normally write
  `bindings.{{binding_builtin}}`.

Do not write `builtins.{{Builtin}}` in a template that must work for hand-written
builtins; it would render as `builtins.builtins.Name`.

Precedence:

1. per-artifact `replace` section
2. template replacement
3. generated method

Template additions are emitted after generated methods and before per-artifact
`artifact` additions. Names must not collide.

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
