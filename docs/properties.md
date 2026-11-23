# Properties

`Property` is an opt-in field annotation that exposes a Zig field as an engine
property. Inspector hints are derived from the declared value type, so enum,
bitfield, and object pointer fields need no hint options. The implemented
backend uses dynamic `ClassCreationInfo6` callbacks; bindgen/codegen play no
part in it. Declared types, property metadata, and set/get values go through
`godot.conversion`; see [conversion.md](conversion.md).

Status:

- Dynamic `ClassCreationInfo6` backend implemented: `set_func`, `get_func`,
  `get_property_list_func`, `free_property_list_func`.
- `PropertyGroups` section trees and type-derived property hints (enum,
  bitfield, and Node/Resource object pointers) are implemented on the dynamic
  list.
- Property ownership is explicit per field: `.set` and `.deinit` accept
  `.best_effort` or a function. Non-trivial value types (managed builtins,
  `Variant`, `RefCounted` pointers, and structs declaring `deinit`) must declare
  `.deinit` and, unless read-only, `.set`; trivial types keep implicit plain
  assignment and no cleanup. Free-time cleanup stays opt-in per class.
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
  are not the engine accessors)
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
| `hint` | `enums.PropertyHint` or an enum literal such as `.range` | no | Inspector hint; derived from the value type when both `.hint` and `.hint_string` are omitted ([Property hints](#property-hints)), else `.none` |
| `hint_string` | `[]const u8` | no | Inspector hint string; derived for enum/bitfield/object types when both `.hint` and `.hint_string` are omitted, else empty; copied at comptime |
| `type` | `interface.VariantType` or an enum literal such as `.object` | no | Explicit engine Variant type; defaults to `godot.conversion.variantType(T)` |
| `get` | `fn (*Owner) T` or `fn (*const Owner) T` | no | Custom getter; defaults to reading the field value |
| `set` | `.best_effort` or `fn (*Owner, T) void` | no for trivial types; yes for non-trivial writable types | Write mode. `.best_effort` applies the type-driven preset; a function is a custom setter. Omitted on a trivial type means plain assignment. A `read_only` field has no setter. See [Ownership modes](#ownership-modes) |
| `read_only` | `bool` | no | Rejects engine set dispatch while keeping the getter; cannot be combined with `.set` |
| `init` | `Init(T, func, args)` type from `annotations/init.zig` | no | Eager creation-time initializer for the stored value |
| `deinit` | `.best_effort` or `fn (*Owner) void` | no for trivial types; yes for non-trivial types | Cleanup mode for `deinitPropertyFields`. `.best_effort` applies the type-driven preset; a function is a custom cleanup hook. Omitted on a trivial type means no cleanup. Omitted on a non-trivial type is a compile error. See [Ownership modes](#ownership-modes) |

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
- a `RefCounted` object pointer (`godot.reflect.isRefCountedPointer`);
- a struct value type declaring `deinit`.

Everything else is **trivial**: scalars, enums, bitfields, plain value builtins
(`Vector2`, `Color`, ...), non-`RefCounted` object pointers, and structs without
`deinit`. A custom type with a `Conversion` marker is classified by its declared Zig type,
not by its engine type.

Rules:

- Trivial type: both options may be omitted. Omitted `.set` writes `.value` by
  plain assignment; omitted `.deinit` cleans nothing. `.best_effort` is accepted
  and behaves as the preset below.
- Non-trivial writable type: `.set` and `.deinit` are both required. `.set` must
  be `.best_effort` or a function; `.deinit` must be `.best_effort` or a
  function. Leaving either one out is a compile error.
- Non-trivial `.read_only = true`: there is no setter; `.deinit` is required.
  `.read_only` with any `.set` is a compile error.
- The backend never calls a `.deinit` function from a setter; it calls it only
  through `deinitPropertyFields` (directly or via
  `ClassOptions.auto_property_cleanup`). How a new value replaces the old one is
  entirely the `.set` mode's job. (The `.best_effort` setter still calls a
  managed builtin's own `deinit` while replacing it; that is setter behavior, not
  the `.deinit` option.)

A scalar with both options omitted, plus `String` and `RefCounted` properties
with explicit best-effort modes:

```zig
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

// RefCounted pointer: the same preset retains/releases the reference.
target: godot.annotations.Property(?*godot.classes.core.RefCounted, .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(null),
```

### `.best_effort`

The preset reproduces the type-driven behavior the backend used to apply
implicitly; it is still a per-field opt-in:

- setter: managed builtin or `Variant` - deinitialize the previous value, then
  assign the new one; `RefCounted` pointer - retain the new reference before
  releasing the old one, then assign; everything else - plain assignment. The
  new value is stored even when it is the current value.
- cleanup: call the value type's `deinit` when it declares one (managed builtins
  and `Variant` do); otherwise release a `RefCounted` pointer's reference
  (`godot.ownership.releaseRefCounted`; a null optional is a no-op); otherwise
  do nothing.

`.best_effort` is a preset, not a universal owner. It does not deinitialize a
user struct that is not a managed builtin: a struct with `deinit` gets plain
assignment on set, so use a function `.set` (or a `.deinit`-aware custom setter)
when replacing the value must release the old one. It also does not inspect a
converter's engine type: a custom struct whose engine is a `RefCounted` pointer
is plain assignment and no-op cleanup, as above. Use the pointer type directly or
write custom functions when setter retain/release is wanted.

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

Hints are derived from the declared Zig value type independently of
`Constants`. A same-class `Constants` declaration only adds registered
enum/bitfield metadata: `class_name` and the matching usage bit.

These rules apply to every type-derived hint:

- The hint applies only to visible properties (`usage != 0`). A hidden property
  gets no automatic hint and no added usage; it stays hidden.
- Setting either `.hint` or `.hint_string` disables the type-derived hint and
  the registered enum/bitfield enrichment, even when the value is `.none` or an
  empty string. The explicit values are used verbatim.
- Scalar and plain builtin value types (`Vector2`, `Color`, `String`, ...) have
  no type-inherent hint. Typed `Array`/`Dictionary` hints are not derived yet.
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
custom getter is read-only policy and never manages lifetime. See
[Lifetime](#lifetime).

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
- a `RefCounted` pointer must own the reference the field promises, or be a null
  optional pointer;
- a user struct value with `deinit` must be fully initialized.

Cleanup stays explicit: the field's `.set` mode handles overwrite and its
`.deinit` mode (or none) handles free-time cleanup; both apply to initialized
values as usual (see [Lifetime](#lifetime)).

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
follow the declared `PropertyFor` through `godot.conversion`
(`decodeVariant`/`encodeVariant`), including a `Conversion` marker. An
explicit `.type` does not bypass the required `.variant` support and does not
change how a value is encoded. Use it only when the declared type's engine
representation and the desired engine type are consistent; see
[conversion.md](conversion.md).

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
the shape check for the function-valued `.deinit` only: `.best_effort` is not a
custom hook, and `deinitPropertyFields` branches on the declared mode, using
`deinitBestEffort` for the preset. `requiresExplicitOwnership` is the value-type
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
  including zero-usage ones, converts the borrowed `Variant` with
  `godot.conversion.decodeVariant`, and calls the setter. Unknown names,
  read-only properties (`.read_only`), and type mismatches return false. `nil`
  and null objects are accepted for optional object pointers. Engine object
  values are additionally checked at runtime with `Object.isClass` against the
  declared engine class (engine subclasses are accepted) before the backend
  stores or retains the pointer; a Variant holding an object of the wrong class
  is rejected and takes no reference. Extension-class targets need no extra
  check because `decodeVariant` resolves only that exact registered extension
  instance.
- `get_func` calls the getter and writes an owned `Variant` built with
  `godot.conversion.encodeVariant` into the engine return slot.
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

- `type` from `.type` when provided, otherwise
  `godot.conversion.variantType(value_type)` for every descriptor, including
  zero-usage ones: hidden properties still dispatch through set/get, so a value
  type with no Variant type (for example `Variant` itself, whose transparent
  storage has no tag) is a compile error even when omitted from the list unless
  an explicit `.type` is supplied. `Property(Variant)` is supported with an
  explicit `.type`; because `Variant` is non-trivial it also needs `.set` and
  `.deinit` (or just `.deinit` when read-only). The `.best_effort` setter
  deinitializes the previous Variant on overwrite; a custom setter owns it. A
  type with no conversion support at all is rejected before this fallback, and
  an explicit `.type` does not rescue it. Supported default values are scalars,
  enums, packed bitfields, codegen builtins, engine/extension object class
  pointers, and custom types with a `Conversion` marker whose engine type is
  one of those.
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
  [Ownership modes](#ownership-modes): a managed builtin or `Variant`
  deinitializes the previous value then assigns; a `RefCounted` pointer retains
  the new reference before releasing the old one then assigns; everything else
  is plain assignment.
- no `.set` is allowed only on a trivial type and is plain assignment.

A non-trivial writable type cannot omit `.set` or `.deinit`. `.deinit` never
participates in the write path, even when it is a function. `Property(Variant)`
is non-trivial: it needs an explicit `.type`, `.set`, and `.deinit` (a read-only
Variant needs `.type` and `.deinit` but no `.set`).

A field managed by `.best_effort` must hold a valid owned value on every set: an
owned `RefCounted` pointer must start as `null` or already own a reference.
Engine builtin fields cannot use a normal field default because builtin
construction is a runtime dispatcher call; initialize them with an `.init`
initializer or in `InitCallback` with owned constructors
(`String.fromLatin1`, `String.fromUtf8`, `StringName.fromLatin1(..., false)`,
...). Never store a cached literal from `fromComptimeLatin1` in such a field:
the `.best_effort` setter deinitializes the previous value on overwrite and its
cleanup deinitializes it on free, and cached literals must never be
deinitialized. A custom `.set` must make the same guarantee for whatever it
stores.

The primitive policy lives in `godot.ownership` and `godot.builtins`:
`godot.builtins.isManaged` for managed builtins,
`godot.ownership.retainRefCounted` / `godot.ownership.releaseRefCounted` for
`RefCounted` values, `godot.ownership.retainObjectReference` when only the engine
`Object*` is known, and `godot.ownership.releaseConstructedBase` for a base
constructed by `classdb_construct_object3`.

### Custom accessors

A custom `.get` overrides only the read path. A function `.set` overrides only
the write path; `.best_effort` and an omitted setter are backend modes. When only
`.get` is present, a trivial field still uses plain assignment and a non-trivial
field still requires `.set`.

- a custom `.set` for a deinit type receives the value decoded by
  `godot.conversion.decodeVariant`; it must store, transfer, or deinitialize it;
- object pointers from `decodeVariant` are borrowed, so a custom setter is not
  handed a reference;
- a custom getter must return a borrowed handle for deinit types: return the
  stored value (a shallow copy is fine), not a freshly constructed owned
  `String`/`Array`. `godot.conversion.encodeVariant` copies the returned value
  and the backend does not deinit it, so returning a fresh owned value leaks one
  reference per read;
- a custom getter for an object pointer returns a borrowed pointer;
  `encodeVariant` takes a Variant-owned `RefCounted` reference or stores a
  borrowed non-`RefCounted` pointer, so the object must stay valid for the
  lifetime of the returned Variant.

### Explicit cleanup

`annotations.deinitPropertyFields(T, instance)` runs each field's declared
`.deinit` mode; it never falls back to the value type. Per `Property` field, in
order:

1. a function `.deinit` is called (it handles null and any other state);
2. `.deinit = .best_effort` runs the preset: call the struct value type's
   `deinit` when it declares one (managed builtins and `Variant` do), otherwise
   release a `RefCounted` reference (`godot.ownership.releaseRefCounted`; a null
   optional pointer is skipped, never read as non-null), otherwise nothing;
3. no `.deinit` mode: nothing happens, even for a managed builtin, `Variant`,
   `RefCounted` pointer, or struct declaring `deinit`.

The helper ignores custom accessors, usage flags, and engine dispatch: it walks
the declared fields directly. It does not free the instance or its storage, and
it does not track what was already cleaned, so call it once per instance. The
caller guarantees that the fields hold valid values: never call it while a field
still holds `undefined`. A class without `Property` fields is a no-op; a
non-struct type is a compile error.

`.deinit` is `.best_effort` or a normal `fn (*Owner) void`. A function's shape is
validated when the `Property` is declared and its owner pointer when the field is
resolved for the owning class (`godot.annotations.property.descriptors` or
cleanup). It runs only when cleanup is requested (a manual
`deinitPropertyFields` call or the opt-in class flag), not on engine set: a
`.deinit` function is cleanup only, never a set hook. It is the field's entire
cleanup policy; there is no automatic fallback underneath it.

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
[registration.md](registration.md#instance-lifecycle).

## Non-goals

- no static ClassDB property registration; [classdb.md](classdb.md#d1-the-dynamic-property-backend-stays-the-only-property-backend)
  records why the dynamic backend stays the only one for instanced classes
- no extension method registration here; it is [classdb.md](classdb.md) work
- no group prefixes or a manual `.depth` option; nesting sets the depth and names
  are verbatim labels
- no explicit enum/bitfield hint labels; they come from the Zig declaration's
  field names
- no indexed or array properties
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
  `Variant`, `RefCounted` pointers, and structs declaring `deinit` require
  explicit `.set`/`.deinit` modes, and `deinitPropertyFields` never falls back to
  the value type
- no automatic value tracking; cleanup runs only through an explicit `.deinit`
  mode (see [Lifetime](#lifetime))
- no bindgen/codegen changes for extension properties

## Future work

- Add group prefixes and explicit section depths.
- Add explicit enum/bitfield hint labels through `Constant(value, opts)`.
- Add typed `Array`/`Dictionary` hints.
- Add property revert callbacks.
