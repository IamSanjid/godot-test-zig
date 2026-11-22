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
  signal. Types use the property Variant mapping with one exception: `Variant` is
  a valid untyped argument for a signal (`VariantType.nil`), while a property
  requires an explicit `.type` for it.
- Signals are declared flat on the class, like `Override` markers and the
  generated signal structs. Discovery collects the type declarations that are
  `Signal` markers, in declaration order.
- A class with no signal declarations registers no signals. Two declarations with
  the same engine name are a compile error.

Signals are declaration markers, not fields: they carry no per-instance state, so
they cannot be a field type like `Property`.

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
- The result is the `enums.Error` from `Object.emitSignal`.
- The arguments are converted to owning `Variant`s, emitted, and deinitialized
  after the call returns. The engine borrows them during dispatch (deferred
  connections copy their arguments into the message queue), so releasing them
  after `emit_signal` returns is safe. Converting a value copies it or takes a
  reference: heap-backed builtins (`Packed*Array`, `String`, `Array`,
  `Dictionary`) and large plain builtins (`Transform3D`, `Basis`, ...) are
  refcounted or heap-allocated inside the Variant by the engine, and `deinit`
  releases that; object arguments keep the engine object alive for the call (a
  `RefCounted` gains one reference that is released again). The Zig values you
  passed keep their own ownership. See [variants.md](variants.md).
- A signal declared on an engine class is a codegen struct, not a `Signal`
  marker, so it has no `emit`; use `Object.emitSignal` for those.

## Argument conversion

Emit converts each declared argument with `Variant.initDeclared`, the same
conversion properties, methods, and callables use. Accepted forms, object
reduction, and nil rules are in
[variants.md](variants.md#declared-type-conversions); emit applies them in the
Zig-to-engine direction and accepts nothing else. Each argument Variant is
`deinit`ed after dispatch.

Extension-declared arguments are exact-class, so a signal that should accept a
subclass or an engine-base pointer declares an engine class.

## Receiving: no chain conversion back

`Variant.as(*X)` resolves an engine object back to the extension instance through
`Object.asInstance(X)`, which looks the binding up under a token derived from the
Zig type (`Object.typeToken`) and set by `setInstance`. Consequences:

- Resolution is exact-class. Asking for `*Y` on an `X` instance returns `null`
  rather than reinterpreting memory, so there is no unsafe cast to guard.
- "Convert the engine `Node` back to `X`" is only meaningful while the object
  *is* an X instance, which requires X to be registered. Otherwise declare the
  engine class and receive the engine pointer.
- Because there is no chain cast, `Variant.typeFor(*X)` and `Variant.init/as`
  are the whole contract; the emit helper does not add a second one.

## Not in this version

- No typed `connect`/`disconnect`/`isConnected` for user signals: they need a
  custom `Callable`, and Zig closures are designed but not implemented yet. See
  [callables.md](callables.md). Engine-class signals already get codegen
  namespaces with those wrappers (`Node.Ready`), so `Object.connect` is the
  fallback for now.
- No named/struct argument form; `emit` takes a positional tuple.
- Engine classes' own signals remain codegen structs (`Node.Ready`) and are
  emitted through `Object.emitSignal` with a `StringName`. Codegen drops
  `signal.arguments`, so the codegen struct carries only the name and the
  connect trio; the raw bindgen struct keeps typed argument fields.
- No vararg signals (Godot signals have a fixed arity).

## Verification

Discovery and conversion are covered by compile-only checks and unit tests under
`zig build test-godot`. Engine-facing behavior needs an editor run:

- GDScript sees the declared signal and its argument types and can connect to it.
- Emitting from Zig delivers the scalar and the `source` object; the object
  arrives as the extension instance's engine base, not as the Zig struct.
- A `RefCounted` argument survives the dispatch and is released afterwards.
- A signal that is not declared (or not registered) still refuses `connect`,
  which is the behavior this work fixes.

