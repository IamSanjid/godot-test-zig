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

Declaration markers (`Override`, `Signal`, `Constants`) carry no `marker.Kind`.
They describe the class rather than a field: `Override` names a virtual
implementation, `Signal` declarations are collected by marker type, and
`Constants` by its wrapped declarations. See [classdb.md](classdb.md).

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
- Creation only resets the wrapper to `value = null`; `.Node` and `.Call` do not
  run then. Resolution triggers are in
  [registration.md](registration.md#onready).
- `OnReady.get()` panics in safety-enabled builds when the value is unset. Use
  `getPtr()` / `getPtrConst()` when absence is valid.
- `initOnReadyFields(T, Base, owner, base)` resolves all marked fields manually.
- With `auto_onready = true`, registration installs this route if the class has
  a `Base` field and extends `Node`. Auto-OnReady with `OnReady` fields is a
  compile error for non-`Node` classes. Users can skip auto mode and call
  `initOnReadyFields` manually.

### `Init(T, func, args)`

Shared deferred call wrapper: it records a function and a comptime argument
tuple and exposes `call(OwnerT, Base, owner, base)`. It only describes the call;
the caller decides when to run it.

- Used by `OnReady(T).Call(func, args)`, resolved on `post_enter_tree` or the
  reload notification, and by the `Property` `.init` option, run during creation
  after the instance is attached.
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
  `.get`, `.set`, `.read_only`, `.init`, `.deinit`. The option table and
  semantics are in [properties.md](properties.md#options).
- `.usage` accepts `enums.PropertyUsageFlags`, a named flag literal such as
  `.exported` / `.none`, or an anonymous struct of flags. Zero-usage properties
  are hidden from `get_property_list` but stay reachable through engine
  set/get.
- `Property(T, options).Init(func, args)` appends `.init = Init(T, func, args)`;
  chain it only once.
- Registration installs the dynamic `ClassCreationInfo6` property callbacks;
  static ClassDB property registration is deliberately not used. See
  [classdb.md](classdb.md#d1-the-dynamic-property-backend-stays-the-only-property-backend).
- Backend behavior, `.init`/`OnReady` timing, `.read_only` details,
  `.type` overrides, managed-builtin defaults, and lifetime cleanup are in
  [properties.md](properties.md).

### `InitCallback(T, f)`

Called during instance creation and on hot-reload recreation, after the instance
is attached and eager `Property` `.init` initializers ran. Creation sends the
post-initialize notification after it; recreation has no such step.

- Member form: receives `*T`, optional `Allocator`, optional `*Extends`.
- Static form: returns `T` or `!T`; it replaces the whole instance, so prefer
  the member form for classes that use `Base` markers or `Property` `.init`.
- On error the instance is detached and its binding freed, then destroyed;
  `DeinitCallback` and property cleanup do not run. Creation also releases the
  engine base, while a reload keeps it. See
  [registration.md](registration.md#instance-lifecycle).
- Runs again when a hot reload recreates the instance; see
  [registration.md](registration.md#hot-reload).
- The allocator is `ClassRegistration.gpa` when present, otherwise
  `instance_allocator`.

### `DeinitCallback(T, f)`

Called before the user instance is freed.

- Must be a member function.
- May accept an `Allocator`.
- Must return `void`.
- Does not free the instance; `instance_allocator.destroy` follows.
- Property fields are not released automatically; release them here (for example
  with `annotations.deinitPropertyFields`) or enable
  `ClassOptions.auto_property_cleanup`, which runs cleanup after this callback.
- Runs from the engine's free-instance callback: during normal destruction, and
  when a hot reload clears the old extension instance during unload. Only
  release Zig-owned values; do not call methods on the engine base.

### `Override(godot_virtual_name, f)`

Provides a virtual implementation under an alternate Zig declaration name.

```zig
pub const CursorShape = godot.annotations.Override("_get_cursor_shape", cursorShape);

fn cursorShape(self: *const @This(), at_position: godot.builtins.Vector2) i32 {
    return 0;
}
```

- The first argument is the exact engine virtual name, taken from
  `Virtual.Meta.godot_name`. `_get_cursor_shape` exists on `Control`, so this
  example class must extend `Control`.
- Registration uses the override map before falling back to declaring a Zig
  method named after the generated virtual.
- The override function must match the generated virtual signature.
- This is useful when the Zig declaration name differs from the generated
  virtual name, or when the virtual name is generated with a conversion you do
  not want to depend on.

### `Signal(engine_name, args)`

Declares one engine signal as a flat class declaration, next to `Extends`:

```zig
pub const HealthChanged = godot.annotations.Signal("health_changed", .{
    .{ "health", i32 },
    .{ "source", ?*godot.classes.core.Node },
});
```

- The first argument is the engine-facing name; the declaration name is only a
  Zig handle, so no case conversion is applied.
- `args` is a tuple of `.{ "engine_arg_name", Type }` pairs in engine order. Names are used
  verbatim and must be unique inside one signal. Types use the property Variant
  mapping, with one exception: `Variant` is a valid untyped signal argument while
  a property needs an explicit `.type` for it.
- Signal registration is what makes `connect`/`emit_signal` work: the engine
  resolves signals from the class signal map.
- A class with no signal declarations registers no signals.

Emit through the marker, which converts each argument:

```zig
_ = TestNode.HealthChanged.emit(self, .{ self.health.get(), self });
```

Object arguments whose declared type is an engine class accept an engine class
pointer that extends it, or an extension instance whose engine base extends it.
Extension-declared arguments accept only that exact instance. See
[signals.md](signals.md) for registration, emit, and what is not supported yet.

### `Constants(decls)`

Wraps a struct of constant declarations as a class-level declaration marker. The declaration
shape inside decides what is registered, and the marker's own declaration name
is free:

```zig
pub const ClassConstants = godot.annotations.Constants(struct {
    pub const MAX_HEALTH = 100;                        // loose constant
    pub const State = enum(i32) { idle, running = 3 }; // State.IDLE, State.RUNNING
    pub const Flags = bitpack struct(u32) {            // Flags.FIRST, Flags.SECOND
        first: bool = false,
        second: bool = false,
        _pad0: u30 = 0,
    };
});
```

- Loose constant names, enum variants, and bitfield fields are converted to
  engine constants (`maxSpeed` -> `MAX_SPEED`, `running` -> `RUNNING`); the
  enum/bitfield declaration name is used verbatim as the engine enum name.
- A `bitpack struct` registers each bool field as a bitfield constant with
  `is_bitfield = true`. The value comes from the real bitpack layout; internal
  `_`-prefixed fields are skipped.
- A `u64` value above the `i64` maximum is carried in the sign bit, matching the
  API contract for 64-bit constants.
- Non-exhaustive enums, non-bool bitfield fields, unsupported declarations,
  empty markers, and duplicate `(enum, name)` pairs are compile errors.
- A class may declare several `Constants` markers; their entries append in
  declaration order. A class with none registers no constants.

Constants are class-level metadata written once during registration. Signals
are too, and additionally expose `emit` on the marker for instance code to
call. See [classdb.md](classdb.md).

### `NotificationCallback(T, f)`

Called for every engine notification.

```zig
pub fn onNotification(self: *@This(), p_what: i32, p_reversed: bool) void
```

- Exactly three parameters.
- Does not free the instance.

## Annotation initialization

`annotations.initAnnotFieldsDefault(T, Base, owner, base)` resets the
default-initialized annotation wrappers. Today this is the `OnReady` family
(`value = null`); it runs no user code and resolves nothing. `Property` fields
are ordinary default-initialized wrappers and are not part of this pass.
Property `.init` creation-time initializers are also separate:
`annotations.initPropertyFields` runs them during creation, after the instance
is attached and before `InitCallback` (see
[registration.md](registration.md#instance-lifecycle)). Add new
default-initialized annotation types here.

`reflect.initFieldsDefault` is separate: it initializes ordinary Zig field
defaults after `allocator.create` and is useful outside annotations.
