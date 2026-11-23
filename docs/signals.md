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
  compile error.
- `Variant` is the one untyped argument: it registers as `VariantType.nil`, and
  emit stores its transparent storage. Every other argument derives a concrete
  Variant type; a property storing `Variant` instead needs an explicit `.type`.
- A signal argument is declared and emitted as its declared Zig type.
  Registration never converts a value; it only derives metadata. Emit applies
  the conversion layer described below.
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

For every argument, registration derives the engine metadata through
`godot.conversion`:

- `variantType(Declared)` for the `PropertyInfo` type; `Variant` registers as
  `.nil`.
- `engineClassName(Declared)` for the `class_name` string, so a converter whose
  engine type is `?*Node` registers `"Node"`. The name is empty for non-object
  arguments.
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
- Each declared argument is encoded with
  `godot.conversion.encodeVariant(Declared, value, &temp)` into an owning
  `Variant`. All argument Variants are deinitialized after `emit_signal`
  returns. The engine borrows them during dispatch; deferred connections copy
  their arguments into the message queue.
- The declaration already validated `.variant` support, so emit adds no separate
  support check. `encodeVariant` still applies the compile-time gate and the
  conversion rules once per declared type.
- A custom converter argument must be an exact `T` value. `to_engine` runs
  inside `encodeVariant`, and the engine-side intermediate is released after the
  Variant is created; `from_engine` is not used on emit.
- Optional object values may be `null`; `encodeVariant` stores `Variant.nil`.
  Engine class pointers may be subclass pointers, and extension instances reduce
  to their engine base; extension-declared arguments accept only that exact
  instance. These are the [declared-type rules](variants.md#declared-type-conversions).
- A signal containing a converter argument is analyzed entirely at comptime:
  the declared Zig type selects the engine type for both registration and emit,
  so metadata and values cannot disagree.

## Argument conversion

Emit converts each declared argument through the same `godot.conversion`
primitives properties and virtuals use. The accepted forms and type mapping are
the declared-type rules in [variants.md](variants.md#declared-type-conversions)
and [conversion.md](conversion.md); emit adds no separate coercion, nil rule, or
object reduction.

Consequences:

- A signal argument declared as an engine class accepts a pointer to that class
  or a subclass, or an extension instance whose engine base extends it.
- An argument declared as an extension class accepts only that exact registered
  instance. Declare the engine class when a signal should accept a subclass or a
  plain engine pointer.
- A converter argument carries the declared Zig type, not its engine type. Emit
  and registration both derive the engine representation from the marker; a
  caller cannot pass the engine value directly.

The temporary Variants own their payload. For direct builtins and converters to
builtins, `initDeclared` copies or takes an owning reference and `deinit`
releases it. Object arguments are borrowed from the Variant for the duration of
the call; a `RefCounted` gains one Variant-owned reference that is released
again. The Zig values passed to `emit` keep their own ownership. See
[conversion.md](conversion.md#ownership) and [ownership.md](ownership.md).

## Receiving: no chain conversion back

Typed `connect` is not implemented, so a Zig receiver gets the engine argument
`Variant` and extracts it explicitly with `Variant.asDeclared(T)` or
`godot.conversion.decodeVariant(T, ...)`. Both use the same declared-type rules
as emit, but no automatic reverse registration exists.

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
- Because there is no chain cast, `Variant.typeFor(*X)` /
  `conversion.variantType(*X)` report only `.object`; they do not carry
  per-class metadata or imply a cast path.
- `decodeVariant` additionally runs a converter's `from_engine` and releases the
  engine intermediate when it owns storage, exactly as described in
  [conversion.md](conversion.md#decodevariant). A receiver that stores the
  result owns it according to its declared type.

## Not in this version

- No typed `connect`/`disconnect`/`isConnected` for user signals: they need a
  custom `Callable`, and Zig closures are designed but not implemented yet. See
  [callables.md](callables.md). Engine-class signals already get codegen
  namespaces with those wrappers (`Node.Ready`), so `Object.connect` is the
  fallback for now.
- Callables have not migrated to `godot.conversion`, so a signal argument with a
  custom converter has no closure-side receive equivalent yet.
- No named/struct argument form; `emit` takes a positional tuple.
- Engine classes' own signals remain codegen structs (`Node.Ready`) and are
  emitted through `Object.emitSignal` with a `StringName`. Codegen drops
  `signal.arguments`, so the codegen struct carries only the name and the
  connect trio; the raw bindgen struct keeps typed argument fields.
- No vararg signals (Godot signals have a fixed arity).

## Verification

Discovery, declaration-time support validation, registration metadata
derivation, and emit conversion are covered by compile-only checks and unit
tests under `zig build test-godot` (`tests/annotations/signal.zig` and
`tests/conversion.zig`). The optional
[`test-godot-live`](build.md#live-godot-tests) step reads the registered signal
list back from a headless Godot process; emission and connection behavior still
need an engine or editor run.
