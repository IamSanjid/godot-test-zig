# Annotations

Annotations are optional markers. Registration detects them at compile time and
adds behavior only when present. A class with no annotations still registers.

## Markers

Every annotation family declares `pub const marker = marker.Kind.<family>`.
`kindOf`/`is` report that identity. Discovery checks the kind first, then applies
the family's own payload validation, so a lookalike struct cannot register
behavior by writing a marker value alone. `Init` is a deferred call descriptor
and declares no marker. `Base` declares kind `base`, but Base discovery itself
stays structural and annotation-free in `reflect/base.zig` so `Variant` and
registration can run without annotations.

### Marker identity

| Kind | Declared by | Role |
|---|---|---|
| `base` | `Base(Extends)` | Field wrapper: stores the engine base pointer |
| `on_ready` | `OnReady(T)` | Field wrapper: deferred initialization |
| `property` | `Property(T, options)` | Field wrapper: dynamic engine property |
| `init_callback` | `InitCallback(T, f)` | Class declaration: creation/reload callback |
| `deinit_callback` | `DeinitCallback(T, f)` | Class declaration: free-instance callback |
| `notification_callback` | `NotificationCallback(T, f)` | Class declaration: notification hook |
| `signal` | `Signal(name, args)` | Class declaration: signal metadata and typed emit |
| `constants` | `Constants(decls)` | Class declaration: integer constants, enums, bitfields |
| `property_groups` | `PropertyGroups(groups)` | Class declaration: inspector section tree |
| `conversion` | `Conversion(spec)` | Type-attached value conversion |
| `override` | `Override(engine_name, f)` | Class declaration: alternate Zig name for a virtual |

The kind is family identity, not payload validity. It records what the
declaration claims; each family still validates its parameters with its
constructor and discovery code, and a hand-written marker that only carries the
kind is rejected or fails its own checks. A marker with a valid kind but an
invalid signal name, constant declaration, callback signature, `Property` option,
or conversion spec is still a compile error. `Init` is not a marker and is never
discovered.

Kind identity is the first filter for field and declaration discovery; the
family-specific rules in the sections below remain the contract. See
[classdb.md](classdb.md) for how class-level declarations are registered.

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
- The engine-facing `PropertyInfo.type` is `.type` when present, otherwise
  `godot.conversion.variantType(T)`; its engine class name comes from the
  descriptor or `godot.conversion.engineClassName(T)`. Inspector hints are
  derived from the declared Zig type, not the engine type. See
  [conversion.md](conversion.md#consumers).
- Ownership is explicit per field. `.set` and `.deinit` accept `.best_effort`
  or a function. A trivial value type may omit both; a non-trivial one (managed
  builtin, `Variant`, `RefCounted` pointer, or a struct declaring `deinit`) must
  declare both, or just `.deinit` when `.read_only`. `.deinit` is cleanup only
  and is never called by a setter. The preset helpers are
  `godot.annotations.property.setBestEffort`, `deinitBestEffort`, and
  `requiresExplicitOwnership`; the rules are in
  [properties.md](properties.md#ownership-modes).
- `Property(T, options).Init(func, args)` appends `.init = Init(T, func, args)`;
  chain it only once.
- Registration installs the dynamic `ClassCreationInfo6` property callbacks;
  static ClassDB property registration is deliberately not used. See
  [classdb.md](classdb.md#d1-the-dynamic-property-backend-stays-the-only-property-backend).
- Backend behavior, `.init`/`OnReady` timing, `.read_only` details, `.type`
  overrides, and lifetime cleanup are in [properties.md](properties.md).

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

### `Conversion(spec)`

Declares how a custom value type converts to an engine type. Attach it to the
type itself under any declaration name:

```zig
const Duration = struct {
    millis: i32,

    pub const ToInt = godot.annotations.Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Duration) i32 {
        return self.millis;
    }

    fn fromEngine(millis: i32) Duration {
        return .{ .millis = millis };
    }
};
```

- The declaration name is free; discovery scans the type's declarations for the
  `conversion` marker identity. A type may declare at most one marker, and
  lookalike declarations without that identity are ignored.
- The spec has exactly three snake_case keys: `.engine` (a type with direct
  conversion support), `.to_engine` (`fn (T) Engine`), and `.from_engine`
  (`fn (Engine) T`). The marker exports `.Engine`, `.toEngine`, `.fromEngine`,
  and declares `marker.Kind.conversion`.
- Function signatures are validated when `godot.conversion` first uses the
  marker; the marker constructor validates the spec shape and field names.
- The engine type cannot be `Variant` and cannot itself be a converter: there
  are no conversion chains. A marker on a type that already has direct support
  is ignored: direct support wins.
- Properties, signals, and virtuals consume the marker through the shared
  `godot.conversion` queries and primitives; see [conversion.md](conversion.md)
  for support rules, ownership, and examples. There is no per-class or
  per-surface conversion override.

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
- `args` is a tuple of `.{ "engine_arg_name", Type }` pairs in engine order.
  Names are used verbatim and must be unique inside one signal. `Type` is the
  declared Zig type; `Signal` validates `.variant` support at declaration and
  names the signal and argument in the error. `Variant` is the one untyped
  argument (it registers as `.nil`), while a property storing `Variant` needs an
  explicit `.type`.
- Registration derives each argument's `variantType` and `engineClassName`
  through `godot.conversion`; emit encodes the declared values with
  `encodeVariant`. A custom converter argument must be an exact `T` value. See
  [signals.md](signals.md#registration).
- Signal registration is what makes `connect`/`emit_signal` work: the engine
  resolves signals from the class signal map.
- A class with no signal declarations registers no signals.

Emit through the marker, which encodes each declared argument into an owning
Variant and releases it after dispatch:

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
- Non-exhaustive enums, non-`_`-prefixed non-bool bitfield fields, unsupported declarations,
  empty markers, and duplicate `(enum, name)` pairs are compile errors.
- A class may declare several `Constants` markers; their entries append in
  declaration order. A class with none registers no constants.

The inspector hint for a `Property` field comes from its Zig value type, so an
enum or bitpack struct works as a property type without this marker. When the
property is declared on the same class, declaring the type here adds the
registered metadata: the `<Class>.<Name>` `class_name` and the enum/bitfield
usage bit (typed engine docs). Full rules, precedence, and behavior for
unregistered or cross-class types are in
[properties.md](properties.md#enum-and-bitfield-hints).

Constants are class-level metadata written once during registration. Signals
are too, and additionally expose `emit` on the marker for instance code to
call. See [classdb.md](classdb.md).

### `PropertyGroups(decls)`

Declares the inspector section tree for a class's visible `Property` fields.
The marker declaration name is free, at most one marker is allowed per class,
and every visible property must be listed exactly once. Nested groups become
subgroups; depth is the nesting level. Sections are list metadata only: no field
is added and set/get never sees them. The declaration shape, ordering rules, and
compile errors are in [properties.md](properties.md#property-groups).

### `NotificationCallback(T, f)`

Called for every engine notification.

```zig
pub fn onNotification(self: *@This(), p_what: i32, p_reversed: bool) void
```

- Exactly three parameters.
- Does not free the instance.

## Module layout

The flat `godot.annotations` exports remain the declaration and lifecycle API
that user classes call:

- markers: `Base`, `OnReady`, `Property`, `PropertyGroups`, `Signal`,
  `Constants`, `Conversion`, `Init`, `Override`, and the callback markers;
- lifecycle helpers: `initBase`, `initAnnotFieldsDefault`,
  `initPropertyFields`, `deinitPropertyFields`, `initOnReadyFields`;
- discovery: `findSignals`, `findConstants`, and `callComptimeArg1`.

Two submodules hold the implementation and tooling introspection behind those
exports. They are not part of the declaration API:

- `godot.annotations.property` - the `Property`/`PropertyGroups`
  implementation plus descriptor/layout tables (`descriptors`, `layout`,
  `PropertyDescriptor`, `PropertyValueType`), getter/setter/deinit
  introspection, the explicit ownership helpers (`requiresExplicitOwnership`,
  `setBestEffort`, `deinitBestEffort`), field discovery, and the cleanup
  internals.
- `godot.annotations.constants` - the `Constants` internals, constant
  discovery, and the type-hint helpers (`typeHint`, `findEnumName`) that derive
  inspector hints from a Zig value type.

Tooling and tests import the submodules directly; user classes stay on the flat
exports. The facade also exports the `marker` submodule (`marker.Kind`,
`kindOf`, `is`) because discovery compares marker identity, and the
`property`/`constants` submodules above. The same split is summarized in
[CONTEXT.md](../CONTEXT.md#layout).

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
