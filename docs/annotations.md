# Annotations

Annotations are optional markers. Registration detects them at compile time and
adds behavior only when present. A class with no annotations still registers.

## Markers

`OnReady` and `Property` field wrappers declare
`pub const marker: marker.Kind` (`on_ready` / `property`). Their field discovery
filters on that exact kind; lookalike structs without the marker are never
discovered. `Base` declares `marker.Kind.base` for consistency, but Base
discovery is structural and annotation-free (`reflect/base.zig`) and does not use
marker identity.

### `Base(Extends)`

Marks the single field that stores the engine base pointer.

- At most one `Base` field is allowed.
- Required by auto-`OnReady`.
- `initBase` stores the constructed engine base into the marker.
- The marker provides a safe accessor and a debug guard.

### `OnReady(T)`

Marks a field for deferred initialization.

```zig
OnReady(Node).Node("./Child")
OnReady(String).Call(.fromLatin1, .{"..."})
OnReady(u32).Call(f, .{})
```

- `.Node(path)` requires `T` to extend `Node`; it resolves a node path from the
  `Base`.
- `.Call(func, args)` invokes a function or a method resolved on the field's
  value type. It is the shared `Init` wrapper documented below; arguments may be
  plain values, `.owner`, `.base`, `{ .field = name }`, or a nested function
  receiving owner/base pointers. Generic functions must be wrapped with
  `annotations.callComptimeArg1`.
- `OnReady.get()` panics in safety-enabled builds when the value is unset. Use
  `getPtr()` / `getPtrConst()` when absence is valid.
- `initOnReadyFields(T, Base, owner, base)` initializes all marked fields.
- With `auto_onready = true`, registration initializes them on
  `post_enter_tree` if the class has a `Base` field and extends `Node`.
  Auto-OnReady with `OnReady` fields is a compile error for non-`Node` classes.
- Users can skip auto mode and call `initOnReadyFields` manually.

### `Init(T, func, args)`

Shared call wrapper for deferred field initialization: it records a function and
a comptime argument tuple and exposes `call(OwnerT, Base, owner, base)`.

- Used by `OnReady(T).Call(func, args)` and the `Property` `.init` option.
- `func` is a function value or an enum literal naming a method on `T`, such as
  `.fromLatin1`.
- `args` elements may be plain values, `.owner`, `.base`, `{ .field = name }`, a
  function receiving owner/base pointers, or another `Init(...)` type.
- `func` must be a normal runtime function (not generic) with one parameter per
  tuple element. It must return `T` (or the child of `?T`, when `T` is optional);
  fallible functions are not accepted.

### `Property(T, options)`

Marks a field as an engine property and stores its value.

```zig
health: Property(i32, .{
    .usage = .exported,
    .hint = .range,
    .hint_string = "0,100",
}) = .init(100),
```

- Options: `.usage` (required), `.name`, `.hint`, `.hint_string`, `.type`,
  `.get`, `.set`, `.read_only`, `.init`, `.deinit`.
- `.usage` accepts `enums.PropertyUsageFlags`, a named flag literal such as
  `.exported` / `.none`, or an anonymous struct of flags.
- `.type` optionally overrides the engine-facing `PropertyInfo` type;
  it accepts `interface.VariantType` or a concrete enum literal such as `.object`.
  Conversion still follows the declared property value type.
- Zero-usage properties are omitted from `get_property_list` but remain
  reachable through engine set/get dispatch.
- `Property(T, options).Init(func, args)` is shorthand for appending
  `.init = Init(T, func, args)` to the options; chain it only once.
- `.read_only = true` makes a field read-only without a custom setter.
  A custom getter without a custom setter keeps the default `.value` writer and
  remains writable unless `.read_only` is set; `.read_only` plus `.set` is a
  compile error. It is dispatch policy only and does not set
  `PropertyUsageFlags.read_only`.
- Registration installs the dynamic `ClassCreationInfo6` property callbacks;
  static ClassDB property registration is not implemented.
- Fields keep ordinary field defaults where the value type allows one;
  `reflect.initFieldsDefault` assigns them during creation and
  `initAnnotFieldsDefault` does not touch `Property` fields.
- `.init = Init(T, func, args)` assigns the field value eagerly during creation
  (`annotations.initPropertyFields`), after field/`OnReady`/`Base` initialization
  and before `InitCallback`; only fields declaring it are written. It is not
  `OnReady` or engine dispatch, and scene-dependent values use a custom getter or
  an `OnReady` field instead. The initializer must return a valid, owned value;
  cleanup stays explicit.
- Lifetime handling is explicit: the default setter manages only known managed
  builtins and `Variant` (deinitializes the previous value on overwrite) and `RefCounted`
  references (retain new, release previous). Everything else is assigned as-is.
- `annotations.deinitPropertyFields(T, instance)` is an unconditional best-effort
  cleanup helper: a custom `.deinit` hook, then a value type's `deinit`, then a
  `RefCounted` reference release, then a no-op. Nothing calls it automatically
  unless `ClassOptions.auto_property_cleanup = true`; otherwise call it from
  `DeinitCallback` or your own free path.
- `.deinit` optionally names a `fn (*Owner) void` hook. It overrides the helper's
  automatic rules for that field, is called unconditionally, and owns null
  handling.
- Managed builtin fields cannot use a normal field default, because builtin
  construction is a runtime dispatcher call. Initialize them with a `.init`
  initializer or in `InitCallback` with owned constructors such as
  `String.fromLatin1`, `String.fromUtf8`, or `StringName.fromLatin1(..., false)`.
- Never store a cached `fromComptimeLatin1` literal in a managed builtin field:
  the default setter deinitializes the previous value on overwrite, cleanup
  deinitializes it on free, and cached literals must never be deinitialized.
- A `Variant` field owns its payload through `Variant.deinit`; the default
  setter deinitializes the previous Variant on overwrite.

See [properties.md](properties.md) for the option table, descriptors, backend
behavior, and lifetime cleanup.

### `InitCallback(T, f)`

Called during instance creation.

- Member form: receives `*T`, optional `Allocator`, optional `*Extends`.
- Static form: returns `T` or `!T`; it replaces the whole instance, so prefer
  the member form for classes that use `Base` markers or `Property` `.init`.
- Errors abort creation.
- The allocator is `ClassRegistration.gpa` when present, otherwise
  `create_allocator`.

### `DeinitCallback(T, f)`

Called before the user instance is freed.

- Must be a member function.
- May accept an `Allocator`.
- Must return `void`.
- Does not free the instance; `create_allocator.destroy` follows.
- Property fields are not released automatically; release them here (for example
  with `annotations.deinitPropertyFields`) or enable
  `ClassOptions.auto_property_cleanup`, which runs cleanup after this callback.
- Runs from the engine base destructor. Only release Zig-owned values;
  do not call methods on the engine base.

### `Override(godot_virtual_name, f)`

Provides a virtual implementation under an alternate Zig declaration name.

```zig
pub const CursorShape = godot.annotations.Override("_get_cursor_shape", cursorShape);

fn cursorShape(self: *const @This(), at_position: Vector2) i32 {
    return 0;
}
```

- The first argument is the exact engine virtual name, taken from
  `Virtual.Meta.godot_name`.
- Registration uses the override map before falling back to declaring a Zig
  method named after the generated virtual.
- The override function must match the generated virtual signature.
- This is useful when the Zig declaration name differs from the generated
  virtual name, or when the virtual name is generated with a conversion you do
  not want to depend on.

### `NotificationCallback(T, f)`

Called for every engine notification.

```zig
pub fn onNotification(self: *@This(), p_what: i32, p_reversed: bool) void
```

- Exactly three parameters.
- Does not free the instance.

## Annotation initialization

`annotations.initAnnotFieldsDefault(T, Base, owner, base)` initializes the
current default-initialized annotation fields. Today this is the `OnReady`
family; `Property` fields are ordinary default-initialized wrappers and are not
part of this pass. Property `.init` creation-time initializers are also
separate: `annotations.initPropertyFields` runs them during creation, after the
`Base` marker and before `InitCallback` (see
[registration.md](registration.md#instance-lifecycle)). Add new
default-initialized annotation types here.

`reflect.initFieldsDefault` is separate: it initializes ordinary Zig field
defaults after `allocator.create` and is useful outside annotations.
