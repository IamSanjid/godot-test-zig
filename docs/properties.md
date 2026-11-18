# Properties

This document defines the intended `Property` schema and the design constraints
around it. Properties are not implemented yet.

Status:

- **Variant conversion foundation is in place**; properties are not implemented yet.
- Dynamic class-creation property hooks are the first intended backend.
- Static ClassDB property registration is a later optional backend.
- Bindgen/codegen are not expected to change for extension properties.

## Why a field type

`Property` is a **direct field type**, like `OnReady`, not a separate
`pub const` declaration.

```zig
health: godot.annotations.Property(i32, .{
    .usage = godot.annotations.PropertyUsage.exported,
    .hint = .range,
    .hint_string = "0,100",
}) = .init(100),
```

This keeps the property and its storage together and makes field discovery a
normal struct-field scan.

No naming dictionary, no separate registration declaration, no annotation
namespace of property names.

## Type shape

```zig
pub fn Property(comptime T: type, comptime strategy: anytype) type
```

The returned wrapper must:

- store a `value: T`
- expose `init(value: T) Self`
- expose Zig-side `get()` / `set(value)` accessors for the stored value
- expose `PropertyFor = T`
- expose the original `strategy`
- expose an `isSelf` function so Registry can identify marked fields
- not require annotation-field initialization

A field must be initialized normally:

```zig
health: godot.annotations.Property(i32, .{ ... }) = .init(100),
```

`reflect.initFieldsDefault` handles the field default; no new annotation
initialization pass is required for `Property`.

## Strategy schema

The initial strategy keys are:

| Key | Type | Required | Meaning |
|---|---|---|---|
| `usage` | `enums.PropertyUsageFlags` | yes | Godot property usage flags |
| `name` | `?[:0]const u8` | no | Exact engine property name; defaults from the field name |
| `hint` | `enums.PropertyHint` | no | Inspector hint |
| `hint_string` | `[]const u8` | no | Inspector hint string |
| `get` | function | no | Custom getter; defaults to field value |
| `set` | function | no | Custom setter; defaults to field value |

A future additive key is:

| Key | Type | Meaning |
|---|---|---|
| `group` | `[:0]const u8` | Property group/subgroup path; not implemented yet |

There is no `.export` key and no custom `PropertyUsage` enum.

## Usage flags

Use the generated Godot flags directly:

```zig
const enums = @import("../enums.zig");

pub const PropertyUsage = struct {
    pub const none: enums.PropertyUsageFlags = .none;
    pub const default: enums.PropertyUsageFlags = .default;
    pub const exported: enums.PropertyUsageFlags = .{
        .storage = true,
        .editor = true,
    };
};
```

`exported` is a named convenience constant, not a separate enum value or a
mapping layer. `export` is a Zig keyword, so the constant is named `exported`.

Usage examples:

```zig
.usage = godot.annotations.PropertyUsage.none,
.usage = godot.annotations.PropertyUsage.default,
.usage = godot.annotations.PropertyUsage.exported,
.usage = .{ .storage = true, .editor = true },
```

Semantics:

- `none` / zero flags: property is not included in `get_property_list`; it
  remains available through set/get dispatch. It does not appear in the
  inspector and is not serialized.
- `default`: engine `PROPERTY_USAGE_DEFAULT`.
- `exported`: storage + editor, the normal exported-property preset.
- Arbitrary combined flags are allowed; Registry does not pattern-match
  `none`/`default`/`exported`.

The `none` behavior needs a runtime check: if Godot only routes `set`/`get` for
names present in the property list, `none` must instead be represented by a
hidden property-list entry with zero usage.

## Custom get/set

Custom accessors are direct function values in the strategy:

```zig
health: godot.annotations.Property(i32, .{
    .usage = godot.annotations.PropertyUsage.exported,
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

The wrapper does not know the owner type, so Registry validates accessors when
the owner class is registered.

Accepted getter shapes:

```zig
fn(*Owner) T
fn(*const Owner) T
```

Accepted setter shapes:

```zig
fn(*Owner, T) void
```

A missing getter defaults to reading `.value`. A missing setter defaults to
writing `.value`. A getter-only property is read-only from Godot's point of
view.

If custom accessors are used, `.value` is still the storage field. It is not
replaced by the accessors.

## Engine property name

The default engine name comes from the field name using the existing naming
layer:

```zig
naming.comptimeConvert(.godot, .property, field_name)
```

Examples:

```text
health      -> "health"
health_bar  -> "health_bar"
```

`name` overrides the default and is used verbatim. No Pascal or snake fallback
is applied to explicit names.

## Field discovery

Registry scans `T`'s fields for the `Property` wrapper.

Discovery must use explicit marker identity, for example:

```zig
if (comptime reflect.isNormalStruct(F) and @hasDecl(F, "isSelf")) {
    if (F.isSelf(F)) {
        // property field
    }
}
```

The wrapper must not be mistaken for `OnReady` or `Base`.

Only fields declared directly on the registered class are considered for the
first implementation. Inherited engine properties already come from ClassDB.

## Property metadata

Comptime registration produces a per-class property table:

```zig
pub const PropertyDescriptor = struct {
    field_name: [:0]const u8,
    godot_name: [:0]const u8,
    value_type: type,
    usage: enums.PropertyUsageFlags,
    hint: enums.PropertyHint,
    hint_string: []const u8,
    getter: ?...,
    setter: ?...,
};
```

`PropertyInfo` construction needs:

- `type`: the Variant type for `value_type`
- `name`: engine property StringName
- `class_name`: class StringName for object properties
- `hint`: raw hint value
- `hint_string`: String
- `usage`: raw packed usage bits

This mapping belongs to the Variant/property bridge, not bindgen or codegen.

## First backend: dynamic class callbacks

Use `ClassCreationInfo6`:

```zig
set_func
get_func
get_property_list_func
free_property_list_func
```

Registry installs these only when the class has at least one `Property` field.

Behavior:

- `get_property_list_func` returns entries whose usage is not zero.
- Entries with zero usage are omitted from the list but remain in set/get
  dispatch.
- `set_func` matches the exact engine property name and converts the incoming
  `Variant` to the field value type.
- `get_func` converts the field value to an owned `Variant`.
- Property-list storage and its `PropertyInfo`/`StringName`/`String` pointers
  must have a stable lifetime. A lazy per-class static table is acceptable for
  the first implementation.
- `free_property_list_func` can be a no-op for the static table.

No `classdb_register_extension_class_property` and no method registration in
this first backend.

## Later backend: static ClassDB properties

If extension method registration is added later, fixed properties can also be
registered with ClassDB:

```text
classdb_register_extension_class_property
classdb_register_extension_class_property_indexed
classdb_register_extension_class_property_group
classdb_register_extension_class_property_subgroup
```

That backend requires registered getter/setter methods. It should reuse the same
`Property` field schema and descriptor table; backend choice is an internal
registration concern, not an annotation concern.

Dynamic hooks remain useful for computed or instance-dependent property lists
even after static registration exists.

## Grouping

Groups are additive and not part of the first implementation.

Future strategy key:

```zig
.group = "Gameplay/Stats",
```

Possible backends:

- dynamic: property-list group/category/subgroup entries
- static: native ClassDB group/subgroup procedures

The annotation shape must not change when grouping is added.

## Why Variant conversion comes first

Both property backends are Variant-based:

- `get_func` writes an owned `Variant`
- `set_func` receives a borrowed `Variant`
- static getter/setter methods also use Variant callbacks

Required Variant layer:

```zig
Variant.init(T, value) -> Variant
Variant.as(T) -> ?T
Variant.deinit()
Variant.typeFor(T)
```

It must cover:

- canonical scalar slot widths
- enums and packed bitfields
- `real_t` / `f64`
- codegen builtins and binding builtins
- String/StringName/Array ownership
- Object and RefCounted rules
- property type and class-name mapping

Properties must not be implemented before that layer is usable.

## Explicit non-goals for the first property milestone

- no exported-property declaration blocks
- no separate `pub const` property declarations
- no custom `PropertyUsage` enum or matching table
- no bindgen/codegen changes
- no static ClassDB property registration yet
- no extension method registration yet
- no property groups yet
- no indexed properties yet
- no `property_can_revert` / `property_get_revert` yet
- no signals

## Open questions

1. Verify that zero-usage properties are reachable through `Object.set/get`
   when omitted from `get_property_list`.
2. Decide exact getter/setter error behavior for wrong Variant types.
3. Decide ownership for RefCounted-backed property fields.
4. Decide when to add the static ClassDB backend.
