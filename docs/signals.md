# Signals

A signal is class-level metadata: a name plus a fixed argument list that Godot
resolves from the class's signal map. Registration is required - `connect` and
`emit_signal` fail for a signal the engine does not know - and it needs no
callback, no storage, and no instance.

Codegen already emits signal structs for *engine* classes (`Node.Ready`, with
`signal_name` plus `connect`/`disconnect`/`isConnected` wrappers), including
inherited ones with the derived class as `self`. User classes have no codegen, so
the declaration and the typed emit helper live in `annotations`; the
registration call lives in `registration/classdb.zig`.

## Declaration

```zig
pub const HealthChanged = godot.annotations.Signal("health_changed", .{
    .{ "health", i32 },
    .{ "source", ?*godot.classes.core.Node },
});
pub const Pinged = godot.annotations.Signal("pinged", .{});
```

- The first argument is the engine-facing name. The Zig declaration is only a
  handle, so nothing is derived from it and no case conversion happens. Pick a
  readable handle; the string is authoritative.
- The second argument is a tuple of `.{ "engine_arg_name", Type }` pairs in
  engine order. Argument names are used verbatim and must be unique inside one
  signal. `Type` is the **declared Zig type**: a directly supported type or one
  with a `Conversion` marker, provided it has `.variant` support. `Signal`
  validates that support at declaration and names the signal and argument in a
  compile error. A `godot.collections` typed container wrapper is such a
  converter: it registers as the engine container Variant type and emits through
  the Variant path, so wrapper arguments need no ptrcall ownership handling.
- `Variant` is the one untyped argument: it registers as `VariantType.nil`, and
  emit stores its transparent storage. Every other argument derives a concrete
  Variant type; a property storing `Variant` instead needs an explicit `.type`.
- A signal argument is declared and emitted as its declared Zig type.
  Registration never converts a value; it only derives metadata. Emit applies
  the conversion layer described below.
- `godot.ownership.Ref(T)` is a declared converter: it registers as `.object` and
  emits through the Variant path as a borrowed, call-scoped Variant view (the
  caller keeps its own reference alive through the dispatch).
  `godot.ownership.Owned(T)` is manual ownership, not a declared type, so it
  cannot be a signal argument; declare a raw borrowed `?*T` instead or pass
  `.get()` to the managed object. See
  [ownership.md](ownership.md#the-model).
- Signals are declared flat on the class, like `Override` markers and the
  generated signal structs. Discovery collects the type declarations that
  identify as `Signal` markers, in declaration order.
- A `Signal` marker declares `marker.Kind.signal`; `findSignals` checks the kind
  first, then re-derives the marker's structural shape and validates it. A
  lookalike without the kind is never discovered. Identity rules are in
  [annotations.md](annotations.md#marker-identity).
- A class with no signal declarations registers no signals. Two declarations with
  the same engine name are a compile error, as is a duplicate argument name.

Signals are declaration markers, not fields: they carry no per-instance state, so
they cannot be a field type like `Property`.

## Registration

Signal registration writes the class signal map through
`classdb_register_extension_class_signal` after the class itself is registered.
`Registry` runs it from the per-class post-registration callback, immediately
after `classdb_register_extension_class6`, at the same initialization level. A
standalone registration must call
`godot.registration.classdb.postRegistrationCallback(T)` the same way. See
[registration.md](registration.md#class-level-metadata) and the ordering
contract in [classdb.md](classdb.md#registration-pipeline).

For every argument, registration derives the engine metadata through the
internal conversion layer:

- the declared type's engine Variant type for the `PropertyInfo` type;
  `Variant` registers as `.nil`.
- the declared type's engine class name for the `class_name` string, so a
  converter whose engine type is `?*Node` registers `"Node"`. The name is empty
  for non-object arguments, including a typed container wrapper.
- A typed container wrapper argument registers as `.array`/`.dictionary`; the
  wrapper's `Element`/`Key`/`Value` declarations are property-hint metadata and
  do not appear in the signal `PropertyInfo`. The engine container handle in the
  emitted Variant keeps its own element typing.
- The argument name is the declared engine name, verbatim; no naming conversion
  runs.

The engine copies the `PropertyInfo` entries and their strings during the call,
so registration builds them as stack temporaries. Registration performs no
per-argument conversion and does not inspect a value.

Unsupported argument types fail when `Signal(...)` is declared, not during
registration. Registration itself has no value-level failure mode; the runtime
failure is a missing registration, which leaves `connect` and `emit_signal`
reporting a nonexistent signal. `postRegistrationCallback(T)` is null when a
class declares neither signals nor constants.

## Emit

Emit lives on the marker, which is self-contained: it knows its engine name, its
argument list, and how to convert and emit them.

```zig
const TestNode = @This(); // or the class type in a method's scope

_ = TestNode.HealthChanged.emit(self, .{ self.health.get(), self });
_ = TestNode.Pinged.emit(self, .{});
```

- `emit` returns the engine `enums.Error`; `_ =` discards it. Check it when a
  failed emit matters - a signal that does not exist returns
  `ERR_UNAVAILABLE` rather than panicking.
- `owner` is `*T` or `*const T`. The engine object is resolved through the Base
  marker chain (`reflect.engineBasePointer`), so an emit works from any method
  with a `self` pointer, including `_ready(self: *const T)`.
- `values` is a positional tuple in declaration order; the arity is
  compile-checked, and so is every argument type.
- Each declared argument is passed to `emit_signal` as a Variant view:
  canonical scalars/enums/bitfields, plain and managed inline builtins,
  `Variant`, and object pointers use a borrowed view
  ([variants.md](variants.md#ownership)) that needs no cleanup.
  Among object pointers this includes `RefCounted` pointers, `godot.ownership.Ref(T)`,
  and converters whose engine representation is an object pointer. Heap-backed
  builtins (`Transform2D`, `AABB`, `Basis`, `Transform3D`, `Projection`), packed
  arrays, and converters whose engine representation is a managed builtin or
  otherwise owns storage (for example a typed container wrapper) are encoded
  into an owning Variant that is deinitialized after `emit_signal` returns.
- A borrowed `RefCounted` view pins no reference: it aliases the object pointer
  for the synchronous call, so the Zig caller must keep its own reference alive
  through `emit`. Passing a stored `Ref` field's `.get()`, or the `Ref` value
  itself, does that; a raw pointer whose owner is released or moved before the
  call does not. This covers a direct `RefCounted` pointer, a
  `godot.ownership.Ref(T)`, and a converter whose engine representation is a
  `RefCounted` pointer. Owning Variants exist for engine-owned storage, not to
  pin object arguments. A deferred connection copies its arguments into the
  message queue, so deferred delivery is unaffected by the caller's lifetime.
- Borrowed views are call-scoped: they alias the Zig value and must never be
  deinitialized or stored. The engine reads them synchronously; a deferred
  connection copies its arguments into the message queue.
- The declaration already validated `.variant` support, so emit adds no separate
  support check. The conversion layer applies its compile-time gate and the
  declared-type rules once per declared type.
- A custom converter argument must be an exact `T` value. `to_engine` runs
  inside the conversion; a converter with a borrowable engine representation
  (canonical scalar, plain builtin, object pointer) borrows, while converters
  with owned engine storage (a typed container wrapper) are encoded into an
  owning Variant. Optional object values may be `null` (emits as `Variant.nil`);
  object/extension declared-type rules are in
  [variants.md](variants.md#declared-type-conversions).
- A signal containing a converter argument is analyzed entirely at comptime:
  the declared Zig type selects the engine type for both registration and emit,
  so metadata and values cannot disagree.

## Argument rules

Emit converts each declared argument through the same internal conversion layer
properties and virtuals use; the accepted forms and type mapping are the
declared-type rules in [variants.md](variants.md#declared-type-conversions) and
[conversion.md](conversion.md#variant-path). Emit adds no separate coercion, nil
rule, or object reduction. A converter argument carries the declared Zig type;
the engine representation is derived from the marker both for metadata and for
emit. A typed container wrapper argument stays an ordinary `.array`/
`.dictionary` Variant whose handle carries its own element typing; signal
arguments use only the Variant path, so no decoded wrapper reference exists to
release.

## Receiving: no chain conversion back

Typed `connect` is not implemented, so a Zig receiver gets the engine argument
`Variant` and extracts it explicitly with `Variant.asDeclared(T)`. That uses the
same declared-type rules as emit, but no automatic reverse registration exists.
For a converter argument, decode the engine representation with
`Variant.asDeclared(Engine)` and call the marker's `fromEngine`; the layer's
conversion functions are internal and not a user API.

- `Variant.asDeclared(*X)` resolves an engine object back to the extension
  instance through `EngineBaseType(X).asInstance(X)`, which looks the binding up
  under a token derived from the Zig type (`EngineBaseType(X).typeToken(X)`) and
  installed by `attachInstance`.
- Resolution is exact-class for extension types. Asking for `*Y` on an `X`
  instance returns `null` rather than reinterpreting memory, so there is no
  unsafe cast to guard.
- Engine object pointers use `Object.isClass`, so a Variant holding a subclass
  is accepted for an engine-declared argument; the declared runtime class is
  checked. "Convert the engine `Node` back to `X`" is only meaningful while the
  object *is* an X instance, which requires X to be registered.
- Because there is no chain cast, `Variant.typeFor(*X)` reports only `.object`;
  a declared surface derives the same Variant type from the engine
  representation and carries no per-class metadata or cast path.
- The Variant path additionally runs a converter's `from_engine` and releases
  the engine intermediate when it owns storage, following the ownership
  direction in [conversion.md](conversion.md#ownership-direction). A receiver
  that stores the result owns it according to its declared type.

## Not in this version

- No typed `connect`/`disconnect`/`isConnected` for user signals: they need a
  custom `Callable`, and Zig closures are designed but not implemented yet. See
  [callables.md](callables.md). Engine-class signals already get codegen
  namespaces with those wrappers (`Node.Ready`), so `Object.connect` is the
  fallback for now.
- Callables have not migrated to the internal conversion layer, so a signal
  argument with a custom converter has no closure-side receive equivalent yet.
- No named/struct argument form; `emit` takes a positional tuple.
- Engine classes' own signals remain codegen structs (`Node.Ready`) and are
  emitted through `Object.emitSignal` with a `StringName`. Codegen drops
  `signal.arguments`, so the codegen struct carries only the name and the
  connect trio; the raw bindgen struct keeps typed argument fields.
- No vararg signals (Godot signals have a fixed arity).

## Verification

Discovery, declaration-time support validation, registration metadata
derivation, emit conversion, and the borrowed/owned borrow classification are
covered by compile-only checks and unit tests under `zig build test-godot`
(`tests/annotations/signal.zig` and `tests/conversion.zig`), including the
borrowed-`RefCounted` policy, a typed container wrapper argument (its `.array`
Variant metadata and Variant-path emit analysis), and a runtime check of a
borrowed scalar Variant view. The optional
[`test-godot-live`](build.md#live-godot-tests) step reads the registered signal
list back from a headless Godot process and emits a signal with borrowed
`String`/`Array`/`Variant` arguments plus an owned heap-builtin argument into a
connected GDScript receiver, so delivery and script-side copying are exercised
against a real engine. `RefCounted` argument borrowing itself is compile-only.
