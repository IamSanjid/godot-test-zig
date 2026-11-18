# Bindgen backend

Bindgen emits the raw standalone bindings under `src/godot/bindings` by default.

It is independent of codegen and does not use the host runtime. Every generated
binding function takes an explicit `dispatcher: anytype`.

## Output

```text
<output_dir>/
  interface.zig
  enums.zig
  constants.zig
  native.zig
  singletons.zig
  utility/
  builtins/
  classes/
```

`interface.zig` is generated from `gdextension_interface.json`; the rest comes
from `extension_api.json`. The `bindings.zig` module entry point in that
directory is hand-written; bindgen does not generate or overwrite it.

## Responsibilities

- interface enums, handles, aliases, structs and function typedefs
- class bindings with ptrcall method invocation
- builtin bindings with `variant_get_ptr_builtin_method`
- utility category wrappers
- global constants/enums
- native structure aliases
- singleton helpers
- documentation comments, deprecation notes and default reconstruction

## Custom code

Bindgen customization data lives in:

```text
generator/bindgen/custom/
  builtins/<snake>.zig
  classes/<api_type>/<snake>.zig
  classes/<snake>.zig              # classes without api_type
  enums.zig
  interface.zig
  native.zig
  singletons.zig
  utility/<category>.zig
```

Bindgen custom files use the shared section grammar:

```zig
// @section file
// @section artifact name
// @section extend Target[,true]
// @section replace generatedName
```

- `file` adds file-scope code.
- `artifact` appends code to the generated class or builtin. The name identifies
  the added member and is collision-checked.
- `replace` replaces a generated class method with the supplied code. The name
  is the generated Zig identifier (for example `getInstanceId`). Builtin custom
  files currently consume file/artifact/extend sections only; class replacements
  are the supported replacement path.
- `extend` appends raw declarations inside the generated declaration or scope
  named `Target`. Class files use it for the class namespace itself and generated
  scopes such as `Virtual`, `Required`, `Optional`, `Properties`, a signal type,
  a property type, or an options struct. Enum declarations use the generated Zig
  enum type name: global enums in `enums.zig`, class enums in the class file,
  builtin enums in the builtin file, and interface enums in `interface.zig`.
  `,true` keeps the class-scope inheritance behavior, so a child class receives
  the extension too. Enum extensions are emitted inside the enum/bitfield body
  and are inherited by codegen aliases automatically.

Code is inserted as-is and is never compiled directly from the custom tree.
Unused class replacements are errors.

## Templates

Bindgen templates live under:

```text
generator/bindgen/custom/templates/{classes,builtins}/*.zig.tpl
```

They use the shared template grammar:

```zig
// @templates_for Object:derived
// @section artifact helper
pub fn helper(self: *{{Class}}, dispatcher: anytype) void { ... }
// @section_end artifact helper
```

Bindgen templates support artifact additions only; method replacement is a
per-artifact custom section, not a template. Templates may declare private
helpers as well as public methods; a section is inserted as-is inside the
generated class or builtin.
Placeholders are `{{Class}}`, `{{Builtin}}`, `{{dispatcher}}`, `{{api_type}}`,
and `{{method}}`. The codegen-only `{{binding_class}}` and
`{{binding_builtin}}` placeholders are unavailable. Template code must use
imports already emitted for the target artifact; bindgen does not inject
template imports yet.

## Generated builtin conversion methods

Bindgen does not auto-generate `toBinding` / `fromBinding` for every builtin.
Those are a codegen-facing concern. Some bindgen custom builtin files add
specific helpers (`String`, `StringName`, `NodePath`, `Variant`), while the codegen generated
builtins get conversions from the codegen template and hand-written codegen
builtins implement their own.

## Important bindgen rules

- `Variant` is a size-only builtin: it needs custom code and is not in
  `builtin_classes`.
- `Object` is a class, never a builtin.
- Constructors leave the result `undefined`.
- Nontrivial results are initialized before ptrcall.
- Normal enum ptrcall slots are `i64`; bitfields use their canonical `i64`
  width.
- GDExtension interface flag bitfields use the translated C backing type, with
  final padding derived from `@bitSizeOf`; API bitfields use `u32`/`u64`.
- Default literals use cached `String.fromComptimeLatin1`,
  `StringName.fromComptimeLatin1`, and `NodePath.fromComptimeLatin1` where
  applicable and avoid deinitializing cached values. `NodePath` and `String`
  caches are process-lifetime values because those types have no static-buffer
  constructor.
- Compile-time-safe option defaults (primitives, enums, bitfields, Color/Vector/
  Rect types) are non-optional fields and are passed in place. Runtime-owned
  defaults remain optional and are reconstructed by bindgen.
- Only bindgen-constructed runtime defaults are deinitialized; caller-provided
  option values stay caller-owned.
- Class names, enum names and API type paths are deterministic.
- Class `Virtual` metadata includes inherited virtuals, with the derived class as
  the callback self type.
- Generated identifier spelling comes from `src/godot/naming.zig`.
- Generated classes and builtins declare `GodotClassName`, preserving the exact
  engine spelling for reflection.

## Known bindgen caveats

- Vararg fixed arguments are converted with `Variant.wrap`; the `vargs`
  received by bindgen must already be binding Variants. Codegen produces those
  from the library utility's codegen Variants. Bindgen only assembles the final
  engine Variant pointer array. `Variant.wrap` currently supports the fixed
  argument types present in the binding implementation.
- Vararg return conversion is intentionally limited to the cases generated today;
  unsupported types now fail generation explicitly.
- Enum and bitfield slots are canonical; see `abi.md`.
- The hand-written builtins aggregate is not generated by bindgen.
