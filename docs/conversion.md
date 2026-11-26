# Declared-type conversion

Every engine-facing surface declares the Zig type it carries: a
[`Property(T, ...)`](properties.md) field, a [`Signal`](signals.md) argument, and
later a method parameter or virtual signature. That **declared type** crosses the
engine boundary on one of two paths:

| Path | Used by | Carries |
|---|---|---|
| Variant | property set/get, signal registration and emit | an engine `Variant` |
| ptrcall | virtual callbacks; methods when they land | one raw ABI slot |

Conversion is a compile-time model, not a user API. One internal layer decides
which paths a declared type supports, which engine type represents it, and how a
value moves; each surface uses that answer and never reimplements it. User code
does not call conversion functions: it declares types, and a custom type joins
the model with a [`Conversion` marker](annotations.md#conversionspec). A type
that is neither directly supported nor marked is a compile error where a surface
declares it.

## Direct support

A directly supported type needs no marker:

| Declared Zig type | Variant | ptrcall | Engine representation |
|---|---|---|---|
| scalars, `bool`, enums, packed bitfields up to 64 bits | yes | yes | the type itself |
| codegen builtin types (`String`, `Vector2`, `Array`, ...) | yes | yes | the type itself |
| engine and extension class pointers, including optional and `const` forms | yes (`.object`) | yes | the pointer type |
| `Variant` | yes (transparent storage) | yes | `Variant` |
| raw single-item pointer (`*T`, `?*T`), including `?*anyopaque` | no | yes | the pointer type |
| `void`, integers wider than 64 bits, class values, many-pointers, slices, plain structs | no | no | none |

- The Variant column means the value can cross as a `Variant`: scalars and
  object pointers get a concrete Variant type, `Variant` stores transparently,
  and raw pointers have no Variant representation.
- The ptrcall column means the value fits one ABI slot: scalars use canonical
  slot widths (`i64`/`u64`, `f64`, `u8`), builtins their declared layout, and
  object pointers the reference rules in [ownership.md](ownership.md).
- A raw single-item pointer is for buffers, out parameters, and opaque ABI
  slots. It is not an object pointer: no Variant representation, no class name,
  and no engine type beyond the pointer.

The [typed container wrappers](collections.md) are declared types too: their
engine representation is the directly supported `Array`/`Dictionary` builtin, and
they convert elements through the same model.

## The `Conversion` marker

A custom value type joins the model with a marker declaration on the type
itself. The declaration name is free; discovery scans the type's declarations
for the marker identity:

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

The spec has three snake_case keys:

| Key | Meaning |
|---|---|
| `.engine` | The directly supported engine representation type |
| `.to_engine` | `fn (T) Engine`: converts the declared value for the engine |
| `.from_engine` | `fn (Engine) T`: converts an engine value back |

A type may declare at most one marker; lookalikes without the marker identity are
ignored. The marker declares no metadata callback of its own: the Variant type
and engine class name of a converted value are derived from `.engine`, so
registration and conversion always agree.

Rules:

- `.engine` must be a directly supported type with at least one path. A
  converter engine cannot itself be a converter: conversion never chains. A
  ptrcall-only engine therefore limits the marked type to ptrcall consumers.
- `.engine = Variant` is rejected: `Variant` stores transparently and has no
  concrete representation to convert to or from.
- `to_engine` and `from_engine` must be non-generic, non-varargs functions with
  exactly one parameter and the exact parameter/return types above.
- A marker on a type that already has direct support is ignored: direct support
  wins and the type's declarations are not scanned.
- The marker is found on the type itself, never on a class field or through a
  registry. Conversion is a property of the type, not of a surface: properties,
  signals, and future methods share one marker with no per-surface override.

Converter functions follow the ownership direction below. `to_engine` receives
the declared value by value and returns an independent engine value when the
engine type owns storage; `from_engine` receives a borrowed engine value and
must copy or retain whatever it keeps. A `from_engine` that keeps an owning
builtin must retain it rather than hand a borrowed handle on, because the call
that delivered it releases its intermediate; [collections.md](collections.md) is
the worked example.

`godot.ownership.Ref` is the only ownership handle with a marker: a decoded
`Ref` owns one reference its consumer must release. `godot.ownership.Owned`
deliberately has no marker; it is exclusive manual ownership, not a value that
crosses the boundary. Typed construction is likewise outside conversion; see
[ownership.md](ownership.md#construction).

## Ownership direction

Conversion moves exactly one value; it never owns a surface's policy. The two
directions have fixed defaults:

- **Engine to Zig (decode)**: the engine value is borrowed for the call. Object
  pointers stay borrowed. Owning builtins and `Variant` are copied into values
  the consumer owns. A converter's `from_engine` must retain what it keeps, so a
  decoded `Ref` or container wrapper owns one reference.
- **Zig to engine (encode)**: the input value is never consumed by the Variant
  path, which copies or retains into an owning Variant. The ptrcall path writes
  what the slot expects: an object pointer is handed over and the slot takes its
  own reference, while a returned builtin value is moved into engine-owned
  storage. In both directions the caller keeps the references it still owns.

Consumers apply the direction: properties store the decoded value under their
declared `.set`/`.deinit` modes, signal emit keeps the caller's Zig values owned,
and virtual callbacks return raw borrowed pointers. Ownership of the decodes is
stated once in [ownership.md](ownership.md); this page states only how values
cross.

### Variant path

- A borrowed Variant view (`Variant.borrow`) may replace the owning encode for a
  synchronous call that only reads, such as signal emit. A view copies an inline
  value, or a managed builtin's handle bytes without retaining its refcounted
  buffer, into the Variant payload; that is a call-scoped alias, not a
  refcount-free copy and not a way to pass ownership. The classification is
  compile-time: canonical scalars, inline plain and managed builtins, `Variant`,
  and object pointers borrow, including `RefCounted` object pointers (direct,
  `Ref(T)`, or a converter whose engine representation is an object pointer).
  Heap-backed builtins (`Transform2D`, `AABB`, `Basis`, `Transform3D`,
  `Projection`), packed arrays, and converters whose engine representation is a
  managed builtin stay on the owning encode. A borrowed `RefCounted` view pins
  no reference, so the caller must keep its own reference alive for the
  synchronous call; a deferred connection copies and retains its arguments.
- A borrowed view aliases the Zig value for the duration of the call: it is never
  deinitialized or stored. The engine copies deferred signal arguments into its
  own queue, so call-scoped is enough.
- An **owning** Variant payload owns its object references. A pointer read out of
  an owning Variant is borrowed while that Variant is alive; keep the Variant or
  take a `Ref` to keep the object. A borrowed object Variant (`Variant.borrow`)
  owns no reference and must never be deinitialized. See [variants.md](variants.md).

### ptrcall path

- Argument slots point at engine-owned storage valid for the call. Decoded
  argument values are therefore borrowed: object pointers are borrowed, and a
  builtin argument must be copied if it must outlive the call. Never deinitialize
  an argument value.
- Return slots are engine-owned storage the callback writes into, and the engine
  owns the result afterwards. A returned `RefCounted` object is handed to the
  slot, which takes its own reference; the callback keeps whatever reference it
  already owned, so a stored handle is returned with `.get()` and a constructed
  object is moved out of its typed handle before encoding. There is no
  post-encode cleanup.
- Declared object pointers resolve between engine base and extension instance on
  the ptrcall path: an extension instance is represented by its engine base, and
  a received base resolves the registered instance for that exact extension
  class. A pointer to an engine object without the extension binding is null
  (optional) or a runtime error (non-optional).

## Variant and ptrcall consequences

The two paths are independent, and a surface requires the ones it uses:

| Surface | Requires |
|---|---|
| `Property` | Variant for every field, including hidden ones |
| `Signal` | Variant at declaration; registration derives metadata, emit converts |
| Virtuals | ptrcall for every parameter and non-void return |
| Methods (planned) | both: `call` decodes Variant arguments, ptrcall uses slots |

- A signature that cannot support a required path is a compile error at the
  declaration, naming the surface and field/argument. The error is the whole
  gate: a value is never silently converted on a path its type does not support.
- The Variant path has an owning intermediate: registration derives metadata
  only, and a value conversion allocates or retains inside the Variant. The
  ptrcall path has no Variant: it writes one slot, and the engine owns the
  storage on both sides of the call.
- Non-object builtins travel by value or layout, so their ptrcall cost is a copy.
  Object slots are the exception: they are reference storage on the return side
  and borrowed reference storage on the argument side (see
  [ownership.md](ownership.md#engine-boundary)). These are ptrcall rules; the
  canonical scalar/builtin slot layout is a separate, dependency-free ABI
  helper.
- A declared type may support one path only. A raw pointer is ptrcall-only; a
  type whose engine representation is ptrcall-only cannot be a property or
  signal argument. Direct support wins over a marker, so a marker cannot reduce
  a directly supported type's paths.
- `Variant` itself is special: transparent storage, no concrete Variant type.
  A property that stores `Variant` needs an explicit `.type`; a signal argument
  registers as untyped `.nil`.

## Containers and elements

The [`godot.collections`](collections.md) wrappers are declared conversion types
whose engine representation is the container builtin, so they support both
paths:

- On the Variant path a wrapper is the ordinary `.array`/`.dictionary` Variant;
  the engine container's own typing metadata travels with its handle, untouched.
- Element conversion is composed lazily by the wrapper, not by the conversion
  layer: `get` and the append/put/set operations convert one element at a time.
  A wrapper's `Element`/`Key`/`Value` declarations are property-hint metadata,
  not conversion support declarations; they do not type an assigned container.
- A wrapper decoded from the engine owns one engine reference, like `Ref`; a
  wrapper moved into a `Property` field transfers its handle. A method surface
  that receives a decoded wrapper argument must release it once; virtual
  signatures use engine-defined types, so no virtual release path is needed and
  the case does not arise yet.
- `Property` container hints are separate metadata derived from the wrapper
  declarations or explicit `.element`/`.key`/`.value` options; see
  [properties.md](properties.md#typed-container-hints).

## Not in this version

- No conversion chains and no per-class or per-surface overrides.
- No conversion for `void`, integers wider than 64 bits, many-pointers, slices,
  or plain structs without a marker.
- No callables integration: a custom converter argument has no closure-side
  receive yet; see [callables.md](callables.md).
- No methods yet; method argument-release handling for decoded owning values
  comes with that surface.
- No user-facing conversion functions: the declared-type conversion layer is
  internal to the runtime, and test builds reach it through a test-only path
  documented in
  [architecture.md](architecture.md#internal-modules-and-test-access).

## Related

- [annotations.md](annotations.md#conversionspec) - the `Conversion` marker
  declaration surface.
- [ownership.md](ownership.md) - the `Ref`/`Owned`/borrowed model and the engine
  boundary.
- [variants.md](variants.md) - the Variant payload, declared-type operations, and
  borrowed views.
- [collections.md](collections.md) - typed container wrappers as declared
  conversion types and their ownership.
- [properties.md](properties.md#ownership-modes) - property `.set`/`.deinit`
  modes.
- [signals.md](signals.md#registration) - signal registration and emit.
- [virtuals.md](virtuals.md#refcounted-arguments-and-returns) - callback
  argument and return rules.
