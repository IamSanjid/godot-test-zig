# Properties

`Property` is an opt-in field annotation that exposes a Zig field as an engine
property. The implemented backend uses dynamic `ClassCreationInfo6` callbacks;
bindgen/codegen play no part in it.

Status:

- Dynamic `ClassCreationInfo6` backend implemented: `set_func`, `get_func`,
  `get_property_list_func`, `free_property_list_func`.
- Property lifetime is explicit: the default setter manages only known managed
  builtins and `RefCounted` references; free-time cleanup is opt-in per class.
- Read-only properties (`.read_only`) and eager creation-time initializers
  (`.init`) are implemented on the same field annotation.
- Static ClassDB property registration and extension method registration remain
  future work.
- Coverage is compile-time only. The runtime callbacks are analyzed by the
  build, but the repository's build/test steps do not execute them in an engine.

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
- exposes `marker = marker.Kind.property` for discovery

Unknown option names, wrong option value types, a missing `.usage`, and invalid
accessor shapes are compile errors.

## Options

| Key | Type | Required | Meaning |
|---|---|---|---|
| `usage` | `enums.PropertyUsageFlags`, a named flag literal, or an anonymous struct of flags | yes | Engine property usage flags |
| `name` | `?[:0]const u8` | no | Exact engine property name; defaults from the field name |
| `hint` | `enums.PropertyHint` or an enum literal such as `.range` | no | Inspector hint; `.none` when omitted |
| `hint_string` | `[]const u8` | no | Inspector hint string; empty when omitted, copied at comptime |
| `type` | `interface.VariantType` or an enum literal such as `.object` | no | Explicit engine Variant type; defaults to `Variant.typeFor(T)` |
| `get` | `fn (*Owner) T` or `fn (*const Owner) T` | no | Custom getter; defaults to reading the field value |
| `set` | `fn (*Owner, T) void` | no | Custom setter; defaults to writing the field value |
| `read_only` | `bool` | no | Rejects engine set dispatch while keeping the getter; cannot be combined with `.set` |
| `init` | `Init(T, func, args)` type from `annotations/init.zig` | no | Eager creation-time initializer for the stored value |
| `deinit` | `fn (*Owner) void` | no | Cleanup hook for `deinitPropertyFields`; overrides that field's automatic cleanup |

There is no `.export` key (`export` is a Zig keyword), no `.ownership` option,
and no `group` key yet. Groups and other new options must be additive and must
not change the annotation shape.

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
- Non-zero usage: the property is included in `get_property_list` in field
  declaration order.
- Only the usage bits decide list visibility. No other flag combination is
  special.

`Object.set`/`Object.get` route through the extension `set_func`/`get_func`
callbacks before native property lookup and do not consult the property list, so
a zero-usage property stays reachable programmatically while staying out of the
inspector and serialization. This engine contract is the reason hidden
properties are omitted rather than rejected; the repository's coverage of it is
compile-time only.

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
- Accepted setter shape: `fn (*Owner, T) void`.
- Both must be normal runtime functions, not generic ones.
- No getter: the default reads `.value`. No setter: the default writes `.value`.
- A custom getter without a custom setter reads through the getter and writes
  the default `.value`; add `.read_only = true` to reject engine writes. A
  custom setter without a custom getter keeps the default getter and stays
  writable.
- `.read_only = true` is the explicit read-only form; see
  [Read-only properties](#read-only-properties).
- `.value` is always the storage field; accessors do not replace it.
- The wrapper does not know the owner type, so owner-pointer shapes are
  validated when descriptors are collected for the owning class (compile time).

Custom-accessor fields are user-managed: the backend forwards the engine value
through the declared accessor but does not manage the field's lifetime; see
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
- `.read_only` cannot be combined with a custom `.set`; that combination is a
  compile error.
- `.read_only = true` is the only read-only form. It can be used alone or with a
  custom getter. A custom getter without a custom setter remains writable through
  the default `.value` writer unless `.read_only` is set.
- `.read_only` is dispatch policy only. It does not set
  `enums.PropertyUsageFlags.read_only`; that flag is inspector and
  serialization metadata and stays whatever `.usage` declares.
- Zig-side access is unaffected: the wrapper's `set()` method and direct field
  writes still store values.

## Creation-time initializers

`.init = Init(T, func, args)` assigns a property value eagerly during instance
creation, before user `InitCallback` code runs:

```zig
name: godot.annotations.Property(godot.builtins.StringName, .{
    .usage = .exported,
    .init = godot.annotations.Init(
        godot.builtins.StringName,
        .fromLatin1,
        .{ "hero", false },
    ),
}) = .init(undefined),

label: godot.annotations.Property(godot.builtins.String, .{
    .usage = .exported,
    .init = godot.annotations.Init(godot.builtins.String, .fromLatin1, .{"Hero"}),
}) = .init(undefined),
```

The same initializer can be chained with `.Init(...)`:

```zig
the_name: godot.annotations.Property(godot.builtins.StringName, .{
    .usage = .exported,
}).Init(.fromLatin1, .{ "hero", false }),
```

`.Init(func, args)` appends the equivalent `.init = Init(T, func, args)` option.
The chain may be applied once; a property that already declares `.init` cannot
use `.Init(...)` again.

When the value type cannot be built at comptime, declare the wrapper default as
`.init(undefined)`; the creation-time initializer replaces it before any user
code can observe the field.

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
default, and a class without `.init` properties is a no-op. Initializers run
after ordinary field defaults, `OnReady` wrapper defaults, and the `Base` marker,
and before `InitCallback`, in field declaration order, so user init code can rely
on the values already being assigned.

`initPropertyFields` runs before the engine instance binding is installed. An
initializer must not trigger engine callbacks that require the extension
instance binding; the same limitation applies to `InitCallback`. A static-form
`InitCallback` replaces the whole instance and therefore overwrites `.init`
values; use the member form when `.init` values must survive.

`.init` is not engine dispatch and is not coupled to `OnReady`: it never runs on
`_ready` or any scene-tree event. Values that depend on the scene tree use a
custom getter or an `OnReady` field instead.

### Initializer ownership

The initializer result is stored directly in `.value`; custom accessors are not
called, and the backend applies no conversion, retain, or cleanup. The returned
value must be valid and owned according to the field's cleanup model:

- managed builtins must come from owning constructors
  (`String.fromLatin1`, `StringName.fromLatin1(..., false)`, ...), never a cached
  `fromComptimeLatin1` literal;
- a `RefCounted` pointer must own the reference the field promises, or be a null
  optional pointer;
- a user struct value with `deinit` must be fully initialized.

Cleanup stays explicit: the default setter's overwrite handling and
`deinitPropertyFields`/`auto_property_cleanup` apply to initialized values as
usual (see [Lifetime](#lifetime)).

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
use the declared `PropertyFor` (`Variant.asDeclared`/`Variant.initDeclared`). Use
it only when the value type and the desired engine type are consistent; future
custom-type adapter hooks can layer on top of it and the rest of the property
pipeline keeps its normal behavior.

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

`findPropertyFieldNames(T)` scans only fields declared directly on `T`. Identity
comes from `marker.Kind.property`. Marker filtering keeps `Property` fields from
being initialized as `OnReady` fields and vice versa; lookalike structs without
the marker are ignored. Inherited engine properties come from ClassDB; inherited
Zig fields are not scanned.

`descriptors(T)` returns the per-class comptime descriptor table in field
declaration order:

```zig
pub const PropertyDescriptor = struct {
    field_name: [:0]const u8,
    godot_name: [:0]const u8,
    value_type: type,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: [:0]const u8,
    type: ?interface.VariantType,
};
```

Accessors are not part of the descriptor. The backend resolves them through the
`getterFn`/`setterFn` helpers, which also validate the owner pointer shapes and
derive whether a field is read-only; `.read_only` is part of that same decision.
`hasCustomDeinit`/`deinitFn` are the same shape check for the optional `.deinit`
hook, and `deinitPropertyFields` is the cleanup tool built on them.
`hasCustomInitializer` reports the optional `.init` option, and
`initPropertyFields` is the pass that runs it.

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
  `Variant.asDeclared`, and calls the
  setter. Unknown names, read-only properties (`.read_only` or a getter-only
  property), and type mismatches return false. `nil` and null objects are
  accepted for optional object pointers.
  Engine object values are additionally checked at runtime with `Object.isClass`
  against the declared engine class (engine subclasses are accepted) before the
  backend stores or retains the pointer; a Variant holding an object of the
  wrong class is rejected and takes no reference. Extension-class targets need
  no extra check because the conversion resolves only that exact registered
  extension instance.
- `get_func` calls the getter and writes an owned `Variant` built with
  `Variant.initDeclared` into the engine return slot.
- `get_property_list_func` returns a lazy per-class, process-lifetime static
  table of `PropertyInfo` entries for the non-zero-usage descriptors, in
  declaration order. First-use initialization is unsynchronized, matching the
  other static literal caches; initialize/register classes before cross-thread
  use.
- `free_property_list_func` is a no-op: the table and its `StringName`/`String`
  storage are process-lifetime and never freed. The engine copies a
  `PropertyInfo` by dereferencing its pointers, so every entry points at stable
  storage.

`PropertyInfo` contents are derived at comptime:

- `type` from `.type` when provided, otherwise `Variant.typeFor(value_type)`
  for every descriptor, including zero-usage ones: hidden properties still
  dispatch through set/get, so a value type with no Variant mapping (for example
  `Variant` itself) is a compile error even when omitted from the list unless an
  explicit `.type` is supplied. `Property(Variant)` is supported with an explicit
  `.type`; the default setter deinitializes the previous Variant on overwrite.
  Supported default values are scalars,
  enums, packed bitfields, codegen builtins, and engine/extension object class
  pointers.
- `name` from the engine property name.
- `class_name` from `reflect.classNameOf(value_type)` for object properties (the
  extension class name for extension classes); empty otherwise.
- `hint`, `hint_string`, and `usage` from the descriptor.

No `classdb_register_extension_class_property*` call is made. The backend is
dynamic only.

## Lifetime

Property values are not cleaned up automatically when an instance is freed. The
default setter manages only the value families the backend understands;
everything else, including cleanup at free, is the owner's decision.

### Default setter

A field uses the default setter when it declares no custom `.set`. A custom
`.get` changes only the read path; unless `.read_only = true`, the default setter
still writes `.value` using this type-driven policy. On each engine set the
converted value is stored type-driven:

- managed builtin (`annotations.isKnownManagedBuiltin`, generated from
  `extension_api.json` `has_destructor`) or `Variant`: the previous field value
  is deinitialized, then the new value is stored. `Property(Variant)` requires an
  explicit `.type` override.
- `RefCounted` object pointer: the new reference is retained before the previous
  one is released, so assigning the current value back is safe. The value from
  `Variant.as` is borrowed and ownership follows the declared type, so only
  `RefCounted` pointer types are retained/released; non-`RefCounted` object
  pointers (for example `*Object` or `*Node`) are borrowed and stored unchanged.
- everything else (scalars, enums, bitfields, plain value builtins, arbitrary
  user structs): plain assignment. The backend does not guess ownership for user
  types, even when they declare `deinit`.

Plain value builtins such as `Vector2` and user structs are not managed by the
setter. `Variant` is handled separately because it is not a codegen builtin with
`toBinding` conversion. The policy is exposed through
`annotations.isKnownManagedBuiltin`, `annotations.retainRefCounted`, and
`annotations.releaseRefCounted`.

### Custom accessors

A custom `.get` overrides only the read path. A custom `.set` overrides only the
write path. When only `.get` is present, writes still go through the default
setter and its type-driven lifetime policy unless `.read_only` is set.

- a custom `.set` for a deinit type receives the value owned by `Variant.as`; it
  must store, transfer, or deinitialize it;
- object pointers from `Variant.as` are borrowed, so a custom setter is not
  handed a reference;
- a custom getter must return a borrowed handle for deinit types: return the
  stored value (a shallow copy is fine), not a freshly constructed owned
  `String`/`Array`. `Variant.init` copies the returned value and the backend
  does not deinit it, so returning a fresh owned value leaks one reference per
  read;
- a custom getter for an object pointer returns a borrowed pointer;
  `Variant.init` takes a Variant-owned `RefCounted` reference or stores a
  borrowed non-`RefCounted` pointer, so the object must stay valid for the
  lifetime of the returned Variant.

### Explicit cleanup

`annotations.deinitPropertyFields(T, instance)` is an unconditional best-effort
helper. Per `Property` field, in order:

1. a custom `.deinit` hook is called (it handles null and any other state);
2. otherwise a struct value type declaring `deinit` is deinitialized;
3. otherwise a `RefCounted` object pointer releases its reference (a null
   optional pointer is skipped, never read as non-null);
4. otherwise nothing happens.

The helper ignores custom accessors, usage flags, and engine dispatch: it walks
the declared fields directly. It does not free the instance or its storage, and
it does not track what was already cleaned, so call it once per instance. The
caller guarantees that the fields hold valid values: never call it while a field
still holds `undefined`. A class without `Property` fields is a no-op; a
non-struct type is a compile error.

`.deinit` is a normal `fn (*Owner) void` option. Its shape is validated when the
`Property` is declared and its owner pointer when the field is resolved for the
owning class (`descriptors` or cleanup). It runs only when cleanup is requested
(a manual `deinitPropertyFields` call or the opt-in class flag), not on engine
set: the default setter's overwrite handling is unchanged. It overrides the
automatic rules above for its field, so it must handle everything that field
needs, including null. A custom-accessor field gets automatic best-effort cleanup
unless it declares `.deinit`; add a `.deinit` hook when the generic rules are
wrong for that field.

Nothing calls the helper automatically unless the class opts in:

- default (`ClassOptions.auto_property_cleanup = false`, passed to `FreeInstance`
  as `false` by `Registry`): after the optional `DeinitCallback`, the instance
  memory is destroyed and property values are left as-is. Release them in `DeinitCallback`, either by calling
  `deinitPropertyFields` or by releasing the fields directly:

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

The default setter still expects valid values on set: a field it manages must
hold a valid owned value. An owned `RefCounted` pointer must start as `null` or
already own a reference. Engine builtin fields cannot use a normal field default,
because builtin construction is a runtime dispatcher call; initialize them with a
`.init` initializer or in `InitCallback` with owned constructors
(`String.fromLatin1`, `String.fromUtf8`, `StringName.fromLatin1(..., false)`,
...). Never store a cached literal from `fromComptimeLatin1` in such a field: the
setter deinitializes the previous value on overwrite, cleanup deinitializes it on
free, and cached literals must never be deinitialized.

Failure order during creation, including which values are already assigned when
`InitCallback` returns an error, is in
[registration.md](registration.md#instance-lifecycle).

## Non-goals

- no static ClassDB property registration; [classdb.md](classdb.md#d1-the-dynamic-property-backend-stays-the-only-property-backend)
  records why the dynamic backend stays the only one for instanced classes
- no extension method registration here; it is [classdb.md](classdb.md) work
- no property groups/subgroups yet (a planned additive `.group`/`.subgroup`
  option, [classdb.md](classdb.md#phase-b---groups-and-subgroups))
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
- no automatic value tracking or implicit cleanup; the lifetime tools are
  explicit (see [Lifetime](#lifetime))
- no bindgen/codegen changes for extension properties

## Future work

- Add groups/subgroups and the enum hint wiring ([classdb.md](classdb.md)).
- Add property revert callbacks.
- Add a runtime integration test against a real engine: property list
  registration, direct `Object.set`/`get` on a zero-usage property, and
  setter/cleanup round-trips for deinit types and `RefCounted` pointers.
