# Properties

`Property` is an opt-in field annotation that exposes a Zig field as an engine
property. Inspector hints are derived from the declared value type, so enum,
bitfield, and object pointer fields need no hint options. The implemented
backend uses dynamic `ClassCreationInfo6` callbacks; bindgen/codegen play no
part in it. Declared types, property metadata, and set/get values go through the
internal conversion layer; see [conversion.md](conversion.md).

Status:

- Dynamic `ClassCreationInfo6` backend implemented: `set_func`, `get_func`,
  `get_property_list_func`, `free_property_list_func`.
- `PropertyGroups` section trees and type-derived property hints (enum,
  bitfield, Node/Resource object pointers, and typed `Array`/`Dictionary`
  container metadata) are implemented on the dynamic list.
- Typed container properties: a `godot.collections` wrapper value derives the
  engine container hint from its `Element`/`Key`/`Value` declarations with no
  options, while `builtins.Array`/`builtins.Dictionary` storage declares
  `.element`/`.key`/`.value`. Hints do not type or convert the stored container.
  See [Typed container hints](#typed-container-hints).
- Property ownership is explicit per field: `.set` and `.deinit` accept
  `.best_effort` or a function; a custom cleanup hook is `fn (*Owner, *T) void`
  (the owner plus a pointer to the stored value), and `Property.deinit` is the
  conditional per-field cleanup method. Non-trivial value types (managed
  builtins, `Variant`, owning wrappers such as `godot.ownership.Ref` and
  `godot.collections`, and structs declaring `deinit`) must declare `.deinit`
  and, unless read-only, `.set`; trivial types keep implicit plain assignment and
  no cleanup. Free-time cleanup stays opt-in per class; a failed `InitCallback`
  gets a limited best-effort cleanup of fields with a custom `.init`
  initializer (see [Lifetime](#lifetime)). Ownership model:
  [ownership.md](ownership.md).
- Read-only properties (`.read_only`) and eager creation-time initializers
  (`.init`) are implemented on the same field annotation.
- Static ClassDB property registration and extension method registration remain
  future work.
- Unit-test coverage is compile-time only: the build analyzes the runtime
  callbacks. The optional [`test-godot-live`](build.md#live-godot-tests) step
  exercises property registration and default/set/get values headlessly;
  inspector behavior remains manual.

## Why a field type

`Property` is a **direct field type**, like `OnReady`, not a separate
`pub const` declaration:

```zig
health: godot.annotations.Property(i32, .{
    .usage = .exported,
    .hint = .range,
    .hint_string = "0,100",
}) = .init(100),
```

This keeps the property and its storage together and makes discovery a normal
struct-field scan. There is no naming dictionary, no separate registration
declaration, and no annotation namespace of property names.

Every field keeps an ordinary field default (`.init(...)`) where the value type
allows one; `reflect.initFieldsDefault` assigns it during instance creation.
Values that cannot be expressed as a comptime field default, such as
runtime-constructed builtins, use the `.init` option instead:
`annotations.initPropertyFields` runs those initializers eagerly as part of
creation (see [Creation-time initializers](#creation-time-initializers)).

## Type shape

```zig
pub fn Property(comptime T: type, comptime options: anytype) type
```

The returned wrapper:

- stores `value: T`
- exposes `init(value: T) Self`
- exposes Zig-side `get()` / `set(value)` accessors for the stored value (these
  are not the engine accessors). `get()` returns a shallow copy of the stored
  value: for an owning handle or wrapper it aliases the stored handle without
  retaining or copying it, so do not deinit the returned copy; `set(value)` is
  plain assignment with no convert, retain, or release, and ownership of `value`
  transfers to the wrapper.
- exposes `getPtr() *T` / `getPtrConst() *const T` for the stored address. Use
  them when a non-container owning wrapper or a managed builtin must be passed
  without copying (for example
  `Variant.borrow(T, field.getPtrConst()).get()`).
- exposes a conditional `deinit` cleanup method derived from the `.deinit` mode:
  a custom hook field's method takes the owner pointer
  (`field.deinit(owner_ptr)`), a `.best_effort` field's takes no arguments
  (`field.deinit()`), and a field with no mode declares `deinit = void`, so a
  call does not compile
- exposes `PropertyFor = T`
- exposes the original `options` plus normalized option constants (`name`,
  `usage`, `hint`, `hint_string`, `variant_type`, `read_only`,
  `has_custom_get`, `has_custom_set`, `has_custom_init`, `has_custom_deinit`)
- reports `has_custom_set` / `has_custom_deinit` as true only when the option
  holds a function value; `.best_effort` is a mode, not a custom accessor
- exposes `marker = marker.Kind.property` for discovery

Unknown option names, wrong option value types, a missing `.usage`, and invalid
accessor shapes are compile errors.

## Options

| Key | Type | Required | Meaning |
|---|---|---|---|
| `usage` | `enums.PropertyUsageFlags`, a named flag literal, or an anonymous struct of flags | yes | Engine property usage flags |
| `name` | `?[:0]const u8` | no | Exact engine property name; defaults from the field name |
| `hint` | `enums.PropertyHint` or an enum literal such as `.range` | no | Inspector hint; derived from the value type or container declarations/options when both `.hint` and `.hint_string` are omitted ([Property hints](#property-hints)), else `.none` |
| `hint_string` | `[]const u8` | no | Inspector hint string; derived for enum/bitfield/object types and container properties (wrapper declarations or options) when both `.hint` and `.hint_string` are omitted, else empty; copied at comptime |
| `type` | `interface.VariantType` or an enum literal such as `.object` | no | Explicit engine Variant type; defaults to the declared type's engine Variant type |
| `element` | `type` | no | Element type of an `Array` property; derives the container hint. Requires the property's engine type to be `godot.builtins.Array`. Optional for a wrapper-typed property, which derives it from the wrapper's `Element` declaration; an explicit value overrides only that side. See [Typed container hints](#typed-container-hints) |
| `key`, `value` | `type` | no | Key/value types of a `Dictionary` property; derive the container hint. Require the property's engine type to be `godot.builtins.Dictionary`; either side may be declared alone. Optional for a wrapper-typed property, which derives them from `Key`/`Value`; explicit options override only their own side. See [Typed container hints](#typed-container-hints) |
| `get` | `fn (*Owner) T` or `fn (*const Owner) T` | no | Custom getter; defaults to reading the field value |
| `set` | `.best_effort` or `fn (*Owner, T) void` | no for trivial types; yes for non-trivial writable types | Write mode. `.best_effort` applies the type-driven preset; a function is a custom setter. Omitted on a trivial type means plain assignment. A `read_only` field has no setter. See [Ownership modes](#ownership-modes) |
| `read_only` | `bool` | no | Rejects engine set dispatch while keeping the getter; cannot be combined with `.set` |
| `init` | `Init(T, func, args)` type from `annotations/init.zig` | no | Eager creation-time initializer for the stored value |
| `deinit` | `.best_effort` or `fn (*Owner, *T) void` | no for trivial types; yes for non-trivial types | Cleanup mode for the per-field `Property.deinit` method and `deinitPropertyFields`. `.best_effort` applies the type-driven preset; a function is a custom cleanup hook receiving the owner and a pointer to the stored value. Omitted on a trivial type is the `.none` mode: no cleanup, and `Property.deinit` is `void`. Omitted on a non-trivial type is a compile error. See [Ownership modes](#ownership-modes) |

There is no `.export` key (`export` is a Zig keyword), no separate `.ownership`
option (`.set`/`.deinit`, with `.read_only` deciding writability, are the
ownership declaration), and no group option. Sections are declared once per class
with `PropertyGroups`; see [Property groups](#property-groups). New options must
stay additive and must not change the annotation shape.

## Ownership modes

`.set`, `.deinit`, and `.read_only` are the ownership declaration. `.set` and
`.deinit` each accept `.best_effort` or a function; the option names themselves
do not accept `null` or a "default" spelling.

The value type decides whether the modes are required. A type is **non-trivial**
when `godot.annotations.property.requiresExplicitOwnership(T)` is true:

- a managed builtin (`godot.builtins.isManaged`, generated from the engine
  `has_destructor` flag: `String`, `StringName`, `Array`, `Dictionary`, ...);
- `Variant`;
- a struct value type declaring `deinit`; this covers `godot.ownership.Ref` and
  the `godot.collections` wrappers.

Everything else is **trivial**: scalars, enums, bitfields, plain value builtins
(`Vector2`, `Color`, ...), non-`RefCounted` object pointers, and structs without
`deinit`. A custom type with a `Conversion` marker is classified by its declared
Zig type, not by its engine type.

A `RefCounted` value must be stored as `godot.ownership.Ref(T)`: a raw
`RefCounted` pointer is borrowed and is rejected as a property value type at
compile time. Non-`RefCounted` object pointers stay valid borrowed storage.
`godot.ownership.Owned(T)` is manual ownership for unparented objects, not
property storage: it has no `Conversion` marker. See
[Ownership](ownership.md#the-model).

Rules:

- Trivial type: both options may be omitted. Omitted `.set` writes `.value` by
  plain assignment; omitted `.deinit` is the `.none` mode: cleans nothing, and
  the wrapper's `deinit` declaration is `void` instead of a callable method.
  `.best_effort` is accepted and behaves as the preset below.
- Non-trivial writable type: `.set` and `.deinit` are both required. `.set` must
  be `.best_effort` or a function; `.deinit` must be `.best_effort` or a
  function. Leaving either one out is a compile error.
- Non-trivial `.read_only = true`: there is no setter; `.deinit` is required.
  `.read_only` with any `.set` is a compile error.
- A setter never calls a `.deinit` function; cleanup runs only through the
  per-field `Property.deinit` method or a `deinitPropertyFields` pass (directly
  or via `ClassOptions.auto_property_cleanup`). How a new value replaces the old
  one is entirely the `.set` mode's job. (The `.best_effort` setter still calls
  the previous value's own `deinit` for a managed builtin, `Variant`, or struct
  declaring `deinit` while replacing it; that is setter behavior, not the
  `.deinit` option.)

A custom `.deinit` hook is a normal `fn (*Owner, *T) void`: it receives the owner
and a pointer to the stored value (`&field.value`). The owner is there for
cleanup that depends on sibling state; the value pointer is the exact storage to
release. The hook replaces the preset rather than running on top of it, and it is
available both in the bulk `deinitPropertyFields` walk and through the wrapper's
conditional `deinit` method (see [Explicit cleanup](#explicit-cleanup)).

A scalar with both options omitted, plus `String` and `Ref` properties with
explicit best-effort modes. There is no implicit default for a `Property` field;
`Ref` and other owning fields declare an owned initial value, normally
`.init(Ref(T).empty)` for a null wrapper that owns no reference:

```zig
const ResourceRef = godot.ownership.Ref(godot.classes.core.Resource);

// Trivial: no modes; writes are plain assignment, cleanup does nothing.
health: godot.annotations.Property(i32, .{
    .usage = .exported,
}) = .init(100),

// Managed builtin: writable and cleanup modes are explicit.
label: godot.annotations.Property(godot.builtins.String, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}).Init(.fromLatin1, .{"hero"}),

// RefCounted value: the preset deinitializes the replaced wrapper.
target: godot.annotations.Property(ResourceRef, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(ResourceRef.empty),
```

### `.best_effort`

The preset is a per-field opt-in:

- setter: managed builtin, `Variant`, or a struct value declaring `deinit` -
  deinitialize the previous value, then assign the new one. `Ref` and wrapper
  fields fall in this branch: the old wrapper releases its reference, and the
  decoded new wrapper is stored as-is. Everything else - plain assignment. The
  new value is stored even when it is the current value.
- cleanup: call the value type's `deinit` when it declares one (managed builtins,
  `Variant`, `Ref`, and `godot.collections` wrappers do); otherwise do nothing.

The setter and cleanup halves share one classification, so a struct declaring
`deinit` - including `Ref` and wrapper-typed container fields - is leak-free with
no custom functions: the setter deinitializes the replaced value and the cleanup
mode releases the stored one, each exactly once.

`.best_effort` is a preset, not a universal owner. It does not inspect a
converter's engine type: a custom struct whose engine is a `RefCounted` pointer
and that declares no `deinit` is plain assignment and no-op cleanup. Store
`godot.ownership.Ref` or write custom functions when reference release is
wanted.

The public helpers behind the preset live in `godot.annotations.property`:

```zig
const property = godot.annotations.property;
property.setBestEffort(T, &field, value);
property.deinitBestEffort(T, &field);
if (property.requiresExplicitOwnership(T)) { ... }
```

`setBestEffort` and `deinitBestEffort` are the preset bodies. Use them directly
only when a function `.set`/`.deinit` needs the same behavior, or when tooling
must apply the same classification. The option values are the normal declaration
surface.

## Usage flags

Use the generated Godot flags directly. There is no separate usage enum or
mapping layer.

`enums.PropertyUsageFlags.exported` is the storage + editor preset.
`enums.PropertyUsageFlags.default` is engine `PROPERTY_USAGE_DEFAULT`, which
currently has the same bits. Arbitrary combined flags are allowed; the backend
does not pattern-match the presets.

Accepted forms:

```zig
.usage = .exported,                              // named flag literal
.usage = godot.enums.PropertyUsageFlags.exported, // generated value
.usage = .{ .storage = true, .editor = true },   // explicit flags
.usage = .none,                                  // hidden from the property list
```

Semantics:

- Zero usage: the property is omitted from `get_property_list`, but set/get
  dispatch still matches it.
- Non-zero usage: the property is included in `get_property_list`; without a
  `PropertyGroups` marker the list is in field declaration order, otherwise the
  marker's section order applies.
- Only the usage bits decide list visibility. No other flag combination is
  special.

`Object.set`/`Object.get` route through the extension `set_func`/`get_func`
callbacks before native property lookup and do not consult the property list, so
a zero-usage property stays reachable programmatically while staying out of the
inspector and serialization. This engine contract is the reason hidden
properties are omitted rather than rejected; the repository's coverage of it is
compile-time only.

## Property groups

Inspector sections are declared once per class with a `PropertyGroups` marker,
not per field. The marker declaration name is free:

```zig
pub const Groups = godot.annotations.PropertyGroups(.{
    .{
        .name = "Combat",
        .fields = .{ "health" },                 // direct fields, listed order
        .groups = .{
            .{ .name = "Vitals", .fields = .{ "stamina" } },
        },
    },
});
```

- At most one marker is allowed per class, and it must declare at least one
  group.
- `.name` is required and must not be empty. `.fields` and `.groups` are
  optional tuples; unknown keys in a group declaration are compile errors.
- `.fields` entries are Zig field names on the class, not engine property names.
- The marker is authoritative: every visible `Property` field (`usage != 0`)
  must be listed exactly once. Hidden properties may be omitted.
- Unknown field names, hidden properties, duplicate listings, and sections with
  no fields anywhere below them are compile errors.
- Ordering is the section entry, its direct `.fields` in listed order, then its
  child `.groups` depth-first. Direct fields therefore always precede child
  sections inside one section; field declaration order is not preserved across
  sections.
- Nesting sets the depth: a top-level group is depth 0, its child groups depth
  1, and so on. There is no `.depth`, parent name, or prefix option.
- Names are verbatim engine strings. No naming conversion or uniqueness check
  applies, so two sections may share a name.
- Each section becomes one `PropertyInfo` entry: `PROPERTY_USAGE_GROUP` at
  depth 0, `PROPERTY_USAGE_SUBGROUP` above it, `type = NIL`,
  `PROPERTY_HINT_NONE`, and the depth in `hint_string` (for example `",1"` for
  a subgroup at depth 1). The usage is exactly that group bit, with no other
  flag ORed in. A section adds no field and never reaches set/get.
- The resolved list order is available at comptime as
  `godot.annotations.property.layout(T)` for tooling and tests.
- Without a marker, `get_property_list` keeps the visible fields in field
  declaration order, as before.

The marker declares `marker.Kind.property_groups`; discovery checks that identity
and still applies every rule above. See
[annotations.md](annotations.md#marker-identity).

## Property hints

Hints are derived from the declared Zig value type, or from the container
options for a container property, independently of `Constants`. A same-class
`Constants` declaration only adds registered enum/bitfield metadata: `class_name`
and the matching usage bit.

These rules apply to every type-derived hint:

- The hint applies only to visible properties (`usage != 0`). A hidden property
  gets no automatic hint and no added usage; it stays hidden.
- Setting either `.hint` or `.hint_string` disables the type-derived hint and
  the registered enum/bitfield enrichment, even when the value is `.none` or an
  empty string. The explicit values are used verbatim.
- Scalar and plain builtin value types (`Vector2`, `Color`, `String`, ...) have
  no type-inherent hint. A container property derives its hint from the
  wrapper's `Element`/`Key`/`Value` declarations or from explicit
  `.element`/`.key`/`.value` options; a builtin-typed container property without
  options gets no hint.
- Hints are metadata only: they change inspector UI and engine documentation,
  not storage, conversion, or registration.

### Enum and bitfield hints

| Zig value type | Hint | Hint string example |
|---|---|---|
| exhaustive `enum` with variants | `PROPERTY_HINT_ENUM` | `"Idle:0,Running:3"` |
| `bitpack struct` with bool flag fields | `PROPERTY_HINT_FLAGS` | `"First:1,Second:2"` |

- The hint comes from the type declaration itself, including generated Godot
  core enum and bitfield types. Labels are PascalCase from the Zig field names,
  and values are the declared enum values or bitpack masks, joined with commas.
  For a bitpack struct only `bool` fields contribute; `_`-prefixed and non-bool
  fields are ignored. A type with no variants or bool flag fields gets no hint.
- When the same class declares that exact type in one of its `Constants`
  markers, the property also gets `class_name = "<Class>.<Name>"` and
  `PROPERTY_USAGE_CLASS_IS_ENUM` or `PROPERTY_USAGE_CLASS_IS_BITFIELD`, which
  makes engine documentation typed.
- An enum or bitpack type that is unregistered, or declared on another class,
  gets the hint string only: no `class_name`, no added usage bit, and engine
  docs show an int. The editor still gets the dropdown or flag checkboxes.
- The property stays an int in storage and conversion; `Constants` owns the
  registered enum/bitfield values.
- `Constants` declaration rules are in
  [annotations.md](annotations.md#constantsdecls); the registration decision is
  in [classdb.md](classdb.md#d5-integer-constants-come-from-zig-enums-and-bitfields).

### Object pointer hints

The class behind an object pointer value type selects the picker hint, for
engine and extension classes:

| `C` in `*C` / `*const C` / `?*C` / `?*const C` | Hint | Hint string | `class_name` |
|---|---|---|---|
| inherits `Node` | `PROPERTY_HINT_NODE_TYPE` | class name | class name |
| inherits `Resource` | `PROPERTY_HINT_RESOURCE_TYPE` | class name | class name |
| any other class (plain `Object`, non-`Resource` `RefCounted`, ...) | none | empty | class name |

- The hint string and `class_name` are the class's registered name: the engine
  class name for an engine class, the registered extension class name for an
  extension class.
- A class that inherits neither `Node` nor `Resource` gets no picker hint;
  `class_name` is still set, and registration keeps its own class-name fallback.
- Optional and `const` pointer forms resolve the same way.
- An owning `godot.ownership.Ref(C)` property derives the same hint from its
  conversion engine pointer `?*C`, so `Ref(Resource)` gets the resource picker and
  the `Resource` class name. Other owning wrappers resolve through their engine
  type the same way (`annotations/property_hint.zig` `resolveConverted`).

### Typed container hints

A container-valued property declares the engine element typing it describes. A
`godot.collections` wrapper-typed property derives it from the wrapper's
declarations:

```zig
numbers: Property(godot.collections.Array(i32), .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),

resources: Property(godot.collections.Array(?*godot.classes.core.Node), .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),

scores: Property(godot.collections.Dictionary(godot.builtins.String, i32), .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),
```

`builtins.Array`/`builtins.Dictionary` storage declares the same metadata with
the explicit container options:

```zig
plain_array: Property(godot.builtins.Array, .{
    .usage = .exported,
    .element = i32,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),

plain_dict: Property(godot.builtins.Dictionary, .{
    .usage = .exported,
    .key = godot.builtins.String,
    .value = i32,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),
```

Rules:

- Wrapper-typed property: the value type is the wrapper, a declared conversion
  type whose engine type is the container builtin. Hint resolution reads the
  wrapper's public `Element` (or `Key`/`Value`) type declarations; no container
  option is needed. A missing dictionary side is untyped, a `Variant` side is
  untyped, and a non-type declaration is ignored. Contract:
  [collections.md](collections.md).
- Builtin-typed property: `.element` requires the property's engine type to be
  `godot.builtins.Array`; `.key`/`.value` require `godot.builtins.Dictionary`.
  Combining `.element` with `.key` or `.value` is a compile error.
- Explicit `.element`/`.key`/`.value` options are also allowed on a
  wrapper-typed property (its engine type is the container builtin) and merge
  per side with the wrapper declarations: an explicit side wins, the other side
  keeps the wrapper's `Element`/`Key`/`Value`. They never replace the whole
  container resolution.
- Option values are types, not values. Each element or side must have Variant
  conversion support; a type without it is a compile error naming the property
  and option.
- `.key` and `.value` may be declared independently; a missing side is untyped.
  `Variant` on any side means untyped.
- Storage follows the declared value type: builtin storage keeps the container
  builtin, wrapper storage keeps the wrapper (which owns the handle).
  `PropertyInfo.type` is `.array` or `.dictionary` in both cases.

Hint derivation depends only on the element or side type, not on where it was
declared: a wrapper's `Element`/`Key`/`Value` and an explicit container option
resolve through the same rules.

| Declared element/key/value type | Hint | Example hint string |
|---|---|---|
| scalar or plain builtin (`i32`, `String`, `Vector2`, ...) | `PROPERTY_HINT_ARRAY_TYPE` (31) | `Array(i32)` -> `"2/0:"` |
| enum / bitfield | 31 | `"2/2:Idle:0,Running:3"` / `"2/6:First:1,Second:2"` |
| `?*Node` | 31 | `"24/34:Node"` |
| `?*Resource` | 31 | `"24/17:Resource"` |
| another object class | 31 | `"24/17:<Class>"` |
| dictionary key and value typed | `PROPERTY_HINT_DICTIONARY_TYPE` (38) | `Dictionary(String, i32)` -> `"4/0:;2/0:"` |
| key typed, untyped value | 38 | `"4/0:"` |
| untyped key, value typed | 38 | `";2/0:"` |
| `Variant` element, or both dictionary sides `Variant` | none | empty |

- Each side is encoded as `<Variant.Type>/<PropertyHint>:<hint string>` using
  the engine numeric values: `INT` 2, `STRING` 4, `OBJECT` 24; hint values
  `NONE` 0, `ENUM` 2, `FLAGS` 6, `RESOURCE_TYPE` 17, `ARRAY_TYPE` 31,
  `NODE_TYPE` 34, `DICTIONARY_TYPE` 38. Dictionary sides are joined with `;`,
  and an empty side is untyped. This is the engine container type-string format
  documented on `PROPERTY_HINT_ARRAY_TYPE` and `PROPERTY_HINT_DICTIONARY_TYPE`.
- Object elements use the node picker hint for `Node` classes, the resource
  picker hint for `Resource` classes, and the resource hint with the class name
  for other object classes. The class name is the engine representation's class
  name; for an extension class it is the registered name.
- Enum and bitfield elements reuse the scalar enum/bitfield labels in the side's
  hint string. A converter element or side resolves through its engine
  representation, so a converter whose engine type is an enum or bitfield keeps
  the enum/flags hint string instead of falling back to the struct's plain
  representation. Unlike a scalar enum property, the container property does not
  get the same-class `<Class>.<Name>` `class_name` or the enum/bitfield usage
  bit, because its declared value type is the container.
- Precedence: setting either `.hint` or `.hint_string` disables the derived
  container hint, even when the value is `.none` or empty; a hidden property
  (`usage == 0`) derives nothing; a builtin-typed container property without
  options derives nothing. On a wrapper-typed property an explicit
  `.element`/`.key`/`.value` option overrides only that side, and an explicit
  `.hint`/`.hint_string` disables all derivation.

Inspector behavior:

- The engine array editor reads the element spec and constrains the element
  editors to the declared type. Node elements use a node picker, Resource
  elements use the resource editor and expose their own exported properties in
  the inspector, and other object classes fall back to a resource picker with
  the class name. An untyped element is edited as its runtime type.
- The dictionary editor uses the key and value specs for its key and value
  rows.
- These are metadata-driven engine controls. A custom per-element inline UI
  needs an `EditorInspectorPlugin`; the runtime does not provide one.

The hint is metadata only: it does not type the stored container, retype a
container assigned through `Object.set`, or change conversion. Set engine typing
on the container itself with its generated `setTyped`/`setTypedAs` methods or
the owning `godot.collections` wrapper; see
[collections.md](collections.md#engine-metadata). A
builtin `Array`/`Dictionary` property is a managed builtin and a wrapper-typed
property is a struct declaring `deinit`, so both still need explicit
`.set`/`.deinit` ownership modes; for a wrapper field `.best_effort` overwrite and
cleanup release the handle exactly once.

## Custom get/set

Custom accessors are direct function values in the options:

```zig
health: godot.annotations.Property(i32, .{
    .usage = .exported,
    .get = getHealth,
    .set = setHealth,
}) = .init(100),

fn getHealth(self: *@This()) i32 {
    return self.health.value;
}

fn setHealth(self: *@This(), value: i32) void {
    self.health.value = value;
}
```

- Accepted getter shapes: `fn (*Owner) T` and `fn (*const Owner) T`.
- Accepted setter values: `.best_effort` or `fn (*Owner, T) void`.
- Accepted cleanup values: `.best_effort` or `fn (*Owner, *T) void`; the
  per-field `deinit` method and `deinitPropertyFields` dispatch it.
- A function form must be a normal runtime function, not a generic one.
- No getter: the default reads `.value`. No setter on a trivial field: plain
  assignment. A writable non-trivial field cannot omit `.set`; see
  [Ownership modes](#ownership-modes).
- A custom getter on a trivial field without `.set` reads through the getter and
  plain-assigns; add `.read_only = true` to reject engine writes. On a
  non-trivial field a custom getter does not remove the `.set` requirement. A
  custom setter without a custom getter keeps the default getter and stays
  writable.
- `.read_only = true` is the explicit read-only form; see
  [Read-only properties](#read-only-properties).
- `.value` is always the storage field; accessors do not replace it.
- The wrapper does not know the owner type, so owner-pointer shapes are
  validated when descriptors are collected for the owning class (compile time).

Fields with a function `.set` or `.deinit` are user-managed: a function `.set`
owns replacement of the engine value, a function `.deinit` owns cleanup, and the
backend does not manage their lifetime. `.best_effort` is the backend preset. A
custom `.deinit` is `fn (*Owner, *T) void` and receives the owner plus a pointer
to the stored value; a custom getter is read-only policy and never manages
lifetime. See [Lifetime](#lifetime).

## Read-only properties

`.read_only = true` rejects engine set dispatch while keeping the getter active:

```zig
sealed: godot.annotations.Property(u32, .{
    .usage = .exported,
    .read_only = true,
}) = .init(9),
```

- The default getter still reads `.value`; a custom `.get` is used when
  declared.
- `set_func` returns false for the property, so engine `Object.set` does not
  change it. The property still appears in `get_property_list` according to its
  `usage` bits.
- `.read_only` cannot be combined with `.set` (function or `.best_effort`); that
  combination is a compile error.
- `.read_only = true` is the only read-only form. It can be used alone or with a
  custom getter. A non-trivial read-only field must still declare `.deinit`; a
  trivial field may omit both modes.
- On a trivial field, a custom getter without a setter remains writable through
  plain assignment unless `.read_only` is set.
- `.read_only` is dispatch policy only. It does not set
  `enums.PropertyUsageFlags.read_only`; that flag is inspector and
  serialization metadata and stays whatever `.usage` declares.
- Zig-side access is unaffected: the wrapper's `set()` method and direct field
  writes still store values.

A non-trivial read-only property declares only `.deinit`:

```zig
sealed_label: godot.annotations.Property(godot.builtins.String, .{
    .usage = .exported,
    .read_only = true,
    .deinit = .best_effort,
}).Init(.fromLatin1, .{"sealed"}),
```

## Creation-time initializers

`.init = Init(T, func, args)` assigns a property value eagerly during instance
creation, before user `InitCallback` code runs:

```zig
name: godot.annotations.Property(godot.builtins.StringName, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
    .init = godot.annotations.Init(
        godot.builtins.StringName,
        .fromLatin1,
        .{ "hero", false },
    ),
}) = .init(undefined),

label: godot.annotations.Property(godot.builtins.String, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
    .init = godot.annotations.Init(godot.builtins.String, .fromLatin1, .{"Hero"}),
}) = .init(undefined),
```

The same initializer can be chained with `.Init(...)`:

```zig
the_name: godot.annotations.Property(godot.builtins.StringName, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}).Init(.fromLatin1, .{ "hero", false }),
```

`.Init(func, args)` appends the equivalent `.init = Init(T, func, args)` option.
The chain may be applied once; a property that already declares `.init` cannot
use `.Init(...)` again.

When the value type cannot be built at comptime, declare the wrapper default as
`.init(undefined)`; the creation-time initializer replaces it during creation,
before `InitCallback` runs.

The option value must be a type produced by `annotations.Init(T, func, args)`
whose `InitFor` is exactly the property value type `T`; any other value or a
mismatched `InitFor` is a compile error. `func` may be a function value or an
enum literal naming a method on `T`, such as `.fromLatin1`. It must be a normal
runtime function (not generic), it receives one parameter per element of `args`,
and it must return `T` (or the child of `?T`, when the property type is
optional). Initializers are infallible; fallible creation-time work belongs in
`InitCallback`.

`args` is a comptime tuple. Each element is one of:

- a plain value, passed through unchanged;
- `.owner` or `.base`, forwarding the owning instance (`*T`) or the engine base
  pointer;
- `.{ .field = "name" }`, reading an owner field;
- a function receiving owner/base pointers, whose return value is passed;
- another `Init(...)` type, called before the outer initializer.

Only fields declaring `.init` are written; every other property keeps its field
default, and a class without `.init` properties is a no-op. Initializers run in
field declaration order, after ordinary field defaults, the `OnReady` wrapper
reset, the `Base` marker, and the instance attach, and before `InitCallback`.

`initPropertyFields` runs after the engine instance binding is installed, so
engine calls made from an initializer see the extension instance. Fields are
still assigned in declaration order: an initializer that reads, directly or
through engine dispatch, a later `Property` field whose value comes only from
`.init` can see `undefined`; fields with ordinary defaults are valid from the
field-defaults pass. A static-form `InitCallback` replaces the whole instance
and therefore overwrites `.init` values; use the member form when `.init` values
must survive.

`.init` is not engine dispatch and is not coupled to `OnReady`: it never runs on
`_ready` or any scene-tree event. Values that depend on the scene tree use a
custom getter or an `OnReady` field instead. On hot reload, `.init` initializers
and `InitCallback` rerun for the recreated instance, then the engine restores
storage-usage property values; see [registration.md](registration.md#hot-reload).

### Initializer ownership

The initializer result is stored directly in `.value`; `.set`, a custom getter,
and conversion are not called, and the backend applies no retain or cleanup. The
returned value must be valid and owned according to the field's `.deinit` mode:

- managed builtins must come from owning constructors
  (`String.fromLatin1`, `StringName.fromLatin1(..., false)`, ...), never a cached
  `fromComptimeLatin1` literal;
- a `godot.ownership.Ref` must own the reference the field promises: move a
  typed `construct()` or generated engine-method `Ref` result into the field, or
  take a reference with `Ref.init(borrowed)`; `Ref(T).empty` owns nothing;
- a user struct value with `deinit` must be fully initialized; a
  `godot.collections` wrapper must come from `init`, `fromEngine`, `clone`, or
  another owning wrapper and must not be a moved-from copy.

Free-time cleanup stays explicit: the field's `.set` mode handles overwrite and
its `.deinit` mode (or none) handles cleanup when the instance is freed; both
apply to initialized values as usual (see [Lifetime](#lifetime)). A failed
`InitCallback` runs only the limited `.best_effort` pass described there.

## Property type override

`.type` overrides the engine-facing `PropertyInfo` type:

```zig
value: Property(u32, .{
    .usage = .none,
    .type = .string, // enum literal
}),
```

The value must be a concrete `interface.VariantType` value or an enum literal
such as `.int`, `.string`, or `.object`. `.nil` and `.variant_max` are rejected.

This is a metadata override, not a conversion hook: storage and conversion still
follow the declared `PropertyFor` through the internal conversion layer,
including a `Conversion` marker. An explicit `.type` does not bypass the
required `.variant` support and does not change how a value is encoded. Use it
only when the declared type's engine representation and the desired engine type
are consistent; see [conversion.md](conversion.md).

## Engine property name

The default engine name comes from the field name through the naming layer:

```zig
naming.comptimeConvert(.godot, .property, field_name)
```

Examples: `health` -> `"health"`, `healthBar` -> `"health_bar"`.

An explicit `.name` is used verbatim and must not be empty. Two fields on the
same class that produce the same engine name are a compile error, so set/get
dispatch can key on the name without ambiguity.

## Discovery and descriptors

The declaration and lifecycle API stays on the flat `godot.annotations` exports
(`Property`, `PropertyGroups`, `initPropertyFields`, `deinitPropertyFields`).
The implementation and tooling introspection helpers live on the
`godot.annotations.property` submodule.

`godot.annotations.property.findPropertyFieldNames(T)` scans only fields
declared directly on `T`. Identity comes from `marker.Kind.property`. Marker
filtering keeps `Property` fields from being initialized as `OnReady` fields and
vice versa; lookalike structs without the marker are ignored. Inherited engine
properties come from ClassDB; inherited Zig fields are not scanned.

`godot.annotations.property.descriptors(T)` returns the per-class comptime
descriptor table in field declaration order:

```zig
// godot.annotations.property.PropertyDescriptor
pub const PropertyDescriptor = struct {
    field_name: [:0]const u8,
    godot_name: [:0]const u8,
    value_type: type,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    class_name: ?[:0]const u8,
    type: ?interface.VariantType,
};
```

Accessors are not part of the descriptor. The backend resolves them through the
`godot.annotations.property.getterFn`/`setterFn` helpers, which also validate
the owner pointer shapes and derive whether a field is read-only; `.read_only`
is part of that same decision. `setterFn` resolves `.best_effort` and function
setters; `setBestEffort` is the preset body. `hasCustomSetter` and the wrapper's
`has_custom_set` stay false for `.best_effort`. `hasCustomDeinit`/`deinitFn` are
the shape check for the function-valued `.deinit` only:
`deinitFn(Owner, field_name)` resolves and validates the
`fn (*Owner, *Value) void` hook (or null), `.best_effort` is not a custom hook,
and `deinitPropertyFields` branches on the declared mode, using
`deinitBestEffort` for the preset. The wrapper's conditional `deinit` method
forwards the same way. `requiresExplicitOwnership` is the value-type
classification behind the required-mode compile errors.
`godot.annotations.property.hasCustomInitializer` reports the optional `.init`
option, and `initPropertyFields` is the pass that runs it.

## Dynamic backend

Registration installs the callbacks built by `registration/property.zig` into
`ClassCreationInfo6` (through `Registry`):

| Callback | Installed when |
|---|---|
| `set_func`, `get_func` | the class declares at least one `Property` field |
| `get_property_list_func`, `free_property_list_func` | at least one descriptor has non-zero usage |

A class with no `Property` fields leaves all four null. A class whose properties
are all zero-usage still gets set/get, but no property list.

- `set_func` matches the incoming engine `StringName` against every descriptor,
  including zero-usage ones, converts the borrowed `Variant` through the
  conversion layer's Variant path, and calls the setter. Unknown names,
  read-only properties (`.read_only`), and type mismatches return false. `nil`
  and null objects are accepted for optional object pointers. Engine object
  values are additionally checked at runtime with `Object.isClass` against the
  declared engine class (engine subclasses are accepted) before the backend
  stores or retains the pointer; a Variant holding an object of the wrong class
  is rejected and takes no reference. Extension-class targets need no extra
  check because the Variant path resolves only that exact registered extension
  instance.
- `get_func` calls the getter and writes an owning `Variant` built through the
  Variant path into the engine return slot.
- `get_property_list_func` returns a lazy per-class, process-lifetime static
  table of `PropertyInfo` entries: the `PropertyGroups` section tree
  interleaved with the non-zero-usage descriptors, or those descriptors in
  declaration order when no marker is present. First-use initialization is
  unsynchronized, matching the other static literal caches;
  initialize/register classes before cross-thread use.
- `free_property_list_func` is a no-op: the table and its `StringName`/`String`
  storage are process-lifetime and never freed. The engine copies a
  `PropertyInfo` by dereferencing its pointers, so every entry points at stable
  storage.

`PropertyInfo` contents are derived at comptime:

- `type` from `.type` when provided, otherwise the declared value type's engine
  Variant type for every descriptor, including zero-usage ones: hidden
  properties still dispatch through set/get, so a value type with no Variant
  type (for example `Variant` itself, whose transparent storage has no tag) is a
  compile error even when omitted from the list unless an explicit `.type` is
  supplied. `Property(Variant)` is supported with an
  explicit `.type`; because `Variant` is non-trivial it also needs `.set` and
  `.deinit` (or just `.deinit` when read-only). The `.best_effort` setter
  deinitializes the previous Variant on overwrite; a custom setter owns it. A
  type with no conversion support at all is rejected before this fallback, and
  an explicit `.type` does not rescue it. Supported default values are scalars,
  enums, packed bitfields, codegen builtins, engine/extension object class
  pointers, custom types with a `Conversion` marker whose engine type is one of
  those, and the `godot.collections` wrappers (their engine types are the
  container builtins).
- `name` from the engine property name, or the verbatim section name for a
  `PropertyGroups` entry.
- `class_name` from the class behind the engine representation for object
  properties (a custom converter contributes its `.engine` class; extension
  classes use their registered name), from the `<Class>.<Enum>` /
  `<Class>.<Flags>` qualifier for same-class registered enum/bitfield hints, and
  empty otherwise.
- `hint`, `hint_string`, and `usage` from the descriptor.
- A `PropertyGroups` entry uses `type = NIL`, `hint = NONE`, `hint_string` for
  the depth, and exactly `PROPERTY_USAGE_GROUP` or `PROPERTY_USAGE_SUBGROUP` as
  its usage.

No `classdb_register_extension_class_property*` call is made. The backend is
dynamic only.

## Lifetime

Property values are not cleaned up automatically when an instance is freed. Each
field's `.set` and `.deinit` modes are the whole policy; cleanup never infers a
mode from the value type.

### Setter modes

A writable field has exactly one write path:

- a function `.set` is a custom setter. The backend decodes the engine value and
  hands it over; the function owns replacement and any reference transfer.
- `.set = .best_effort` is the type-driven preset described in
  [Ownership modes](#ownership-modes): a managed builtin, `Variant`, or struct
  declaring `deinit` (including `Ref` and the collection wrappers) deinitializes
  the previous value then assigns; everything else is plain assignment.
- no `.set` is allowed only on a trivial type and is plain assignment.

A non-trivial writable type cannot omit `.set` or `.deinit`. `.deinit` never
participates in the write path, even when it is a function. `Property(Variant)`
is non-trivial: it needs an explicit `.type`, `.set`, and `.deinit` (a read-only
Variant needs `.type` and `.deinit` but no `.set`).

A field managed by `.best_effort` must hold a valid owned value on every set: a
`Ref` field must hold an owning wrapper (or a null one) before it is replaced, and
the backend hands the setter an already decoded, owned value that the field then
stores. Engine builtin fields cannot use a normal field default because builtin
construction is a runtime dispatcher call; initialize them with an `.init`
initializer or in `InitCallback` with owned constructors
(`String.fromLatin1`, `String.fromUtf8`, `StringName.fromLatin1(..., false)`,
...). A wrapper-typed field follows the same rule: build the wrapper with
`init`, `fromEngine`, or `clone`, then move it into `.value`, or use
`.Init(godot.collections.Array(T).init, .{})`. There is no implicit empty
default: declare `= .init(Ref(T).empty)` as the field default and move a
generated `construct()` or engine-method `Ref` result into `.value`; a borrowed
pointer needs `Ref(T).init(pointer)`. Never store a cached literal from
`fromComptimeLatin1` in a field
managed by `.best_effort`: the setter deinitializes the previous value on
overwrite and the cleanup deinitializes it on free, and cached literals must
never be deinitialized. A custom `.set` must make the same guarantee for whatever
it stores.

The property preset lives in `godot.annotations.property` and uses
`godot.builtins.isManaged` for managed builtins plus value `deinit` for
`Ref`/wrappers. The low-level `godot.ownership` retain/release helpers are for
runtime internals; property storage uses `Ref` and its `.best_effort` deinit
instead of manual reference counting.

### Custom accessors

A custom `.get` overrides only the read path. A function `.set` overrides only
the write path; `.best_effort` and an omitted setter are backend modes. When only
`.get` is present, a trivial field still uses plain assignment and a non-trivial
field still requires `.set`.

- a custom `.set` for a deinit type receives the value decoded through the
  Variant path; it owns that value and must store, transfer, or deinitialize it.
  For a `Ref` field the decoded value owns one reference, so storing it in the
  field transfers it;
- a property value is never a raw `RefCounted` pointer, so a custom setter is
  never handed a bare borrowed reference for one. Non-`RefCounted` object
  pointers from the Variant path are borrowed;
- a custom getter must return a borrowed handle for deinit types: return the
  stored value (a shallow copy is fine), not a freshly constructed owned
  `String`/`Array`/`Ref`. The Variant path copies the returned value and the
  backend does not deinit it, so returning a fresh owned value leaks one
  reference per read;
- a custom getter for a non-`RefCounted` object pointer returns a borrowed
  pointer; the object must stay valid for the lifetime of the returned Variant.

### Explicit cleanup

`annotations.deinitPropertyFields(T, instance)` runs each field's declared
`.deinit` mode; it never falls back to the value type. Per `Property` field, in
order:

1. a custom `.deinit` function is called with the owner and the stored value:
   the hook shape is `fn (*Owner, *T) void` and the second argument is
   `&field.value`;
2. `.deinit = .best_effort` runs the preset: call the struct value type's
   `deinit` when it declares one (managed builtins, `Variant`, `Ref`, and the
   collection wrappers do), otherwise nothing;
3. no `.deinit` mode: nothing happens, even for a managed builtin, `Variant`,
   `Ref`, or struct declaring `deinit`.

The same policy is available one field at a time through the wrapper's
conditional `deinit` method. A custom hook field's method takes the owner
pointer, a `.best_effort` field's takes no arguments, and a field with no
`.deinit` mode declares `deinit = void`, so there is no callable method:

```zig
// Cleanup from `DeinitCallback`, where `self: *@This()`.
// Custom hook field: `fn (*@This(), *godot.builtins.String) void` receives the
// owner plus a pointer to `title.value`.
self.title.deinit(self);

// `.deinit = .best_effort`: releases the stored value.
self.label.deinit();

// A field with no `.deinit` mode declares `deinit = void`; a call does not
// compile.
```

The per-field method and the bulk helper dispatch the same hook and preset: the
method is for callers cleaning selected fields or already holding the owner, and
`deinitPropertyFields` is the normal all-fields route. A custom hook receives the
owner because cleanup may need owner state beyond the value, and the value
pointer so it releases exactly the stored value. Its shape is validated when the
`Property` is declared (two parameters, `*T` second, void return) and its owner
pointer when the field is resolved for the owning class
(`godot.annotations.property.descriptors` or cleanup). It runs only when cleanup
is requested (the per-field method, a manual `deinitPropertyFields` call, or the
opt-in class flag), not on engine set: a `.deinit` function is cleanup only,
never a set hook. It is the field's entire cleanup policy; there is no automatic
fallback underneath it.

The helper ignores custom accessors, usage flags, and engine dispatch: it walks
the declared fields directly. It does not free the instance or its storage, and
it does not track what was already cleaned, so call it once per instance. The
caller guarantees that the fields hold valid values: never call it while a field
still holds `undefined`. A class without `Property` fields is a no-op; a
non-struct type is a compile error.

Nothing calls the helper automatically unless the class opts in:

- default (`ClassOptions.auto_property_cleanup = false`, passed to `FreeInstance`
  as `false` by `Registry`): after the optional `DeinitCallback`, the instance
  memory is destroyed and property values are left as-is. Release them in
  `DeinitCallback`, either by calling `deinitPropertyFields` or by releasing the
  fields directly:

  ```zig
  pub const Deinit = godot.annotations.DeinitCallback(@This(), deinit);

  fn deinit(self: *@This()) void {
      godot.annotations.deinitPropertyFields(@This(), self);
  }
  ```

- `ClassOptions.auto_property_cleanup = true` (passed to `FreeInstance` as a
  comptime parameter): the free-instance callback calls
  `annotations.deinitPropertyFields(T, instance)` after `DeinitCallback`, then
  destroys the instance. Do not also clean the same fields manually in
  `DeinitCallback` when the flag is on, or they are cleaned twice.

Failure order during creation, including which values are already assigned when
`InitCallback` returns an error, is in
[registration.md](registration.md#instance-lifecycle). The framework does not run
`deinitPropertyFields` there: fields without a default or `.init` initializer may
still be undefined, so a blanket walk is unsafe. It instead releases, while the
instance is still attached, the `.best_effort` values of fields that declare a
custom `.init` initializer. Custom `.deinit` hooks (`fn (*Owner, *T) void`) are
skipped because the owner may be partially initialized, and values `InitCallback`
created or assigned are not tracked. `InitCallback` owns its failure cleanup;
`.init` values on a field whose cleanup is a custom hook still leak on this rare
path. This is a known limitation on the init-failure path, not a cleanup
guarantee.

## Non-goals

- no static ClassDB property registration; [classdb.md](classdb.md#d1-the-dynamic-property-backend-stays-the-only-property-backend)
  records why the dynamic backend stays the only one for instanced classes
- no extension method registration here; it is [classdb.md](classdb.md) work
- no group prefixes or a manual `.depth` option; nesting sets the depth and names
  are verbatim labels
- no explicit enum/bitfield hint labels; they come from the Zig declaration's
  field names
- no indexed property access; array and dictionary fields are one container value
  (the builtin or a `godot.collections` wrapper) with hint metadata
- no `property_can_revert` / `property_get_revert`
- no signals from the property backend; see [signals.md](signals.md)
- no per-instance or computed property lists; the list is a static per-class
  table
- no inheritance of annotation fields (only fields declared directly on the
  class)
- no `OnReady` coupling for properties; `.init` is creation-time only, and
  scene-dependent values use custom getters or `OnReady` fields
- no lazy or per-access property initializers
- no implicit ownership inference for non-trivial types: managed builtins,
  `Variant`, `Ref` and other owning wrappers, and structs declaring `deinit`
  require explicit `.set`/`.deinit` modes, and `deinitPropertyFields` never falls
  back to the value type
- no raw `RefCounted` property storage: store `godot.ownership.Ref` so the owner
  of the reference is in the type, not in a convention
- no automatic value tracking; cleanup runs only through an explicit `.deinit`
  mode (see [Lifetime](#lifetime))
- no automatic engine typing of a container property value: the hint is
  metadata, and typing is set on the container itself (`setTyped`/`setTypedAs`
  or `godot.collections`)
- no per-element custom inspector UI; the engine's default container editors
  use the hint metadata
- no bindgen/codegen changes for extension properties

## Future work

- Add group prefixes and explicit section depths.
- Add explicit enum/bitfield hint labels through `Constant(value, opts)`.
- Add property revert callbacks.
