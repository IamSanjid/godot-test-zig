# Declared-type conversion

`godot.conversion` is the one layer that answers, for a declared Zig type,
whether Godot can carry it, which engine type represents it, and how to convert
between the two. Properties, signals, virtuals, and signal registration use it;
methods and containers will. The hand-written [`Variant`](variants.md) owns the
payload format and the underlying declared-type operations; this page owns the
support, metadata, and ownership policy layered on top.

A declared type is the Zig type written in a `Property`, `Signal` argument, or
virtual signature. Consumers do not reimplement its rules: they ask this module
and call its primitives.

## Paths and support

```zig
pub const Path = enum { variant, ptr };

pub const Support = struct {
    variant: bool, // a Variant representation exists
    ptr: bool,     // a ptrcall representation exists
};
```

The two flags are independent in principle and are reported by `support(T)`:

- `.variant` means the value can cross the engine boundary as a `Variant`. It
  requires a concrete Variant type, except for `Variant` itself, which stores
  transparently and reports no type.
- `.ptr` means the value can cross as one ptrcall slot. Scalars use their
  canonical slot widths (`i64`/`u64`, `f64`, `u8`), builtins use their layout,
  and `RefCounted`/extension object pointers use the special slot rules
  described in [ownership.md](ownership.md#virtual-arguments).

## Direct support

A type has direct support when no marker is needed:

| Declared Zig type | `.variant` | `.ptr` | Engine type |
|---|---|---|---|
| scalars, `bool`, enums, packed bitfields up to 64 bits | yes | yes | the type itself |
| codegen builtin types (`String`, `Vector2`, `Array`, ...) | yes | yes | the type itself |
| engine and extension class pointers, including optional and `const` forms | yes (`.object`) | yes | the pointer type |
| `Variant` | yes (transparent) | yes | `Variant` |
| raw single-item pointer (`*T`, `?*T`), including `?*anyopaque` | no | yes | the pointer type |
| `void`, integers wider than 64 bits, class values, many-pointers, slices, plain structs | no | no | none |

Raw single-item pointers are deliberately split: they have a ptrcall
representation for buffers, out parameters, and opaque ABI slots, but no Variant
representation and no engine class name. They cannot be used where a Variant is
required.

## The `Conversion` marker

A custom value type joins the layer by attaching a `Conversion` marker
declaration to the type itself. The declaration name is free; discovery scans
the type's declarations for the marker identity:

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

Any declaration name works (`GodotConversion` is a common choice, not a
requirement). A type may declare at most one marker; lookalike declarations that
do not carry the conversion marker identity are ignored.

The spec has exactly three snake_case keys:

| Spec key | Meaning |
|---|---|
| `.engine` | The directly supported engine representation type |
| `.to_engine` | `fn (T) Engine`: converts the declared value for the engine |
| `.from_engine` | `fn (Engine) T`: converts an engine value back |

`godot.annotations.Conversion(...)` validates the spec shape and returns the
marker type. The marker exports `.Engine` (type), `.toEngine`, `.fromEngine`,
and `.marker = Kind.conversion`. `conversion.zig` consumes those exports; user
code names the marker once and otherwise uses `godot.conversion` queries.

Ownership of the converter functions:

- `to_engine` receives the declared value by value and returns an independent
  owned engine value when the engine type owns storage.
- `from_engine` receives a borrowed engine value. It must copy if it stores it.
- Object pointer engine types are borrowed pointers in both directions.

## Validation

Every query or primitive validates the marker before using it:

- `.engine` must be a type, and it must be a **directly supported** type with at
  least one path. A converter engine cannot itself be a converter: there are no
  conversion chains. A converter whose engine type is ptr-only therefore supports
  only ptrcall consumers (virtuals); Variant consumers reject it.
- `.engine = Variant` is rejected. `Variant` has transparent storage and no
  concrete representation to convert to or from.
- `to_engine` and `from_engine` must be non-generic, non-varargs functions with
  exactly one parameter and the exact parameter/return types above. A normal
  function value with that signature is accepted; a generic wrapper is not.
- Marking a type that already has direct support is ignored: direct support
  wins and the type's declarations are not scanned. The marker is for types the
  layer does not already know, not an override.
- The marker is found by scanning the type's own declarations, never a class,
  field, or registry. It can only be attached to a type that can carry
  declarations (struct, enum, union, opaque).

Errors that depend on the owner type name the marker declaration and field; a
consumer asking for an unsupported path gets a contextual error naming the
consumer and the type, for example `Property 'Hero.health'` or
`Signal 'health_changed' argument 'health'`.

## Queries

```zig
godot.conversion.support(T)        // Support{ .variant, .ptr }
godot.conversion.engineType(T)     // ?type: T, the marker's Engine, or null
godot.conversion.variantType(T)    // ?interface.VariantType
godot.conversion.engineClassName(T)// [:0]const u8, "" when not an object
```

- `support(T)` follows one marker, if present, and otherwise reports direct
  support. It never chains.
- `engineType(T)` returns `T` for a directly supported type, the marker's
  `.Engine` for a converter, and `null` when neither applies. `void` and
  non-convertible types have no engine type.
- `variantType(T)` is the Variant type of the engine representation. It is null
  for `Variant` itself and for every ptr-only type. A converter inherits its
  engine type's Variant type.
- `engineClassName(T)` is the engine class name of the engine representation, or
  an empty string when that representation is not an object pointer. It follows
  a converter's engine type, so a `Duration` reports `""` and a `NodeRef` over
  `?*Node` reports `"Node"`. Use this query directly; do not reconstruct it from
  `engineType` and a separate class-name lookup.

All four are comptime queries with per-type caches (`SupportCache`,
`EngineTypeCache`, `VariantTypeCache`, `MarkerInfoCache`). The marker is located
and validated once per type; consumers pay no runtime cost.

### Compile-time gates

```zig
godot.conversion.checkSupported(T, .variant, "Property 'Hero.health'");
godot.conversion.checkBoth(T, "virtual '_get_width'");
```

`checkSupported` is the declaration-time gate: it reports the missing path with
the caller's context. `checkBoth` does the same for both paths. The four
primitives also check their own path, so a caller that skipped the gate still
fails at compile time rather than mis-encoding.

## The four primitives

| Primitive | Path | Direction | Result ownership |
|---|---|---|---|
| `decodeVariant(T, *const Variant) ?T` | variant | engine to Zig | declared value: borrowed for object pointers, owned for owning builtins and `Variant` per `Variant.asDeclared` |
| `encodeVariant(T, value, *Variant)` | variant | Zig to engine | writes one owning Variant; the input value stays with the caller |
| `decodePtr(T, ?*const anyopaque) T` | ptr | engine to Zig | borrowed for object pointers, value for scalars/builtins |
| `encodePtr(T, value, ?*anyopaque)` | ptr | Zig to engine | transfers the value into the engine slot |

All four take the declared type `T`, not the engine type. A converter's
`toEngine`/`fromEngine` is applied inside, so consumers never branch on whether
a marker exists.

### `decodeVariant`

- Direct type: `value.asDeclared(T)`, or null on a tag/range/class mismatch.
- Converter: `value.asDeclared(Engine)` first; null when the Variant does not
  hold the engine representation. `fromEngine` then converts. If `Engine` owns
  storage (a managed builtin, a user struct with `deinit`), that intermediate is
  deinitialized after `fromEngine` returns; `fromEngine` must have copied what it
  keeps.
- Object pointers are borrowed. An engine object is class-checked by
  `asDeclared`; an extension pointer resolves only its exact registered
  instance.

### `encodeVariant`

- Direct type: `Variant.initDeclared(T, value)`. For directly supported `T` this
  accepts the forms `initDeclared` already accepts: the exact value, a coercible
  numeric/enum literal, a null optional, or an engine pointer/extension instance
  that extends the declared object class.
- Converter: `toEngine(value)` first, then `Variant.initDeclared(Engine, ...)`;
  the engine intermediate is deinitialized after the Variant copies or retains
  it. The converter value must be an exact `T`, not a literal or a related
  pointer; only the engine intermediate gets the declared-form conveniences.
- The input value is never consumed. The written Variant is owning and must be
  deinitialized by the caller.

### `decodePtr`

- Direct scalar/builtin: reads the canonical slot through `abi.readArgument`.
- Direct object pointer: `RefCounted` uses `ref_get_object` and returns the
  borrowed object; an extension pointer reads the engine base and resolves its
  Zig instance with `asInstance`.
- Converter: decodes the engine type, then calls `fromEngine`. RefCounted and
  extension rules are the engine type's rules, not the declared type's.

### `encodePtr`

- Direct scalar/builtin: writes the canonical slot through `abi.writeReturn`.
- Direct `RefCounted` pointer: `ref_set_object`, which adds an owning reference
  to the engine-owned `Ref<T>` slot. The caller still owns its own reference.
- Direct extension pointer: writes the engine base via `engineBasePointer`.
- Converter: `toEngine(value)` then the engine type's slot rule. For a
  `RefCounted` engine pointer the engine storage takes the reference; the
  converter must not release it as part of encoding.

No primitive calls a Variant constructor on the ptr path or a ptrcall write on
the Variant path. Choose the primitive by what the consumer owns, not by the
declared type.

## Ownership

The declared value and the engine representation have separate lifetimes. The
rule for each direction:

- `to_engine` returns an independent engine value. The Variant path creates the
  output Variant from it and then deinitializes the intermediate, so a converter
  to an owning builtin (`String`, `Array`, ...) must return an owned value that
  the conversion layer may release. The ptr path transfers the returned value to
  the engine slot; a `RefCounted` pointer written through `ref_set_object` gets
  a new reference in engine storage, so the converter must not release that
  reference itself.
- `from_engine` receives a borrowed engine value. The Variant path obtains it
  with `asDeclared`, which returns owned values for owning builtins and borrowed
  pointers for objects; the layer deinitializes the builtin intermediate after
  `from_engine` returns, so `from_engine` must copy anything it keeps. The ptr
  path passes the borrowed scalar/builtin/pointer straight through.
- `encodeVariant` never consumes the caller's declared value; it copies or takes
  an owning reference for the Variant. `encodePtr` transfers the declared value
  into the engine slot.
- `decodeVariant` returns a declared value that the caller owns according to the
  declared type; `decodePtr` returns borrowed object pointers.
- Object pointers are borrowed in both directions. `RefCounted` Variant payloads
  hold one owning reference owned by the Variant; `Ref<T>` ptrcall storage is
  engine-owned. Never assign a raw pointer into `Ref<T>` storage.
- Do not return a cached process-lifetime literal (for example a
  `fromComptimeLatin1` string) from `to_engine`/`from_engine` when the engine
  type owns storage; the layer may deinitialize that intermediate.

Consumer obligations follow from the path table: properties must apply their
declared `.set`/`.deinit` ownership modes to the decoded value; signals must
deinitialize the Variant temporaries they create; virtual callbacks must leave
arguments borrowed and return transferred values. The conversion layer owns the
encoding/decoding ownership transfer, not the consumer's field or callback
lifetime policy.

## Pointer and extension classes

An object pointer type (`*C`, `*const C`, `?*C`, `?*const C`) is both a Variant
`object` and a ptrcall pointer. The converted value is always the engine object:

- Variant path: `initDeclared`/`asDeclared` reduce an extension instance to its
  engine base and resolve it back only for the exact registered extension class
  (subclasses pass for engine classes).
- Ptr path: `decodePtr` turns the engine base into the extension instance via
  `asInstance`; `encodePtr` turns the instance into the engine base via
  `engineBasePointer`.
- `RefCounted` slots use `ref_get_object`/`ref_set_object` in both paths. Never
  assign a raw pointer into `Ref<T>` storage; see
  [ownership.md](ownership.md#refcounted).

A raw pointer (`*i32`, `?*anyopaque`, a buffer type) is not an object pointer. It
has no Variant representation, no class name, and no engine type beyond the
pointer itself; it is only valid where a ptrcall slot is expected. Its pointee
layout is read or written directly by `abi`.

## Consumers

| Consumer | Paths it requires | How it uses the layer |
|---|---|---|
| [`Property`](properties.md) | `.variant` for every field, including hidden ones | `decodeVariant` on set, `encodeVariant` on get; `PropertyInfo.type` from `.type` or `variantType`; class name from the descriptor or `engineClassName`; hints stay declared-type metadata |
| [`Signal`](signals.md) | `.variant` at declaration | registration takes `variantType` and `engineClassName` for the argument metadata; `emit` calls `encodeVariant` into owning temporaries |
| [Virtuals](virtuals.md) | `.ptr` for every parameter and non-void return | `decodePtr` on arguments, `encodePtr` on the return; RefCounted storage is the engine type's slot rule |
| methods (planned) | both | `call_func` will use `decodeVariant`/`encodeVariant`; `ptrcall_func` will use `decodePtr`/`encodePtr`; a signature that cannot support both is a compile error |
| containers (planned) | both | element conversion composes the primitives; no separate container conversion rules |

`Property` ownership classification is separate from conversion support: a
converter is classified by its declared Zig type, not by its engine type. A
custom struct with a `String` engine is still a trivial value type unless it
declares `deinit`; use a function `.set`/`.deinit` when its engine storage needs
explicit release. See [properties.md](properties.md#ownership-modes).

Property hints are also independent of the engine representation: they come from
the declared Zig type in `annotations/property_hint.zig`. A converter to
`?*Node` reports the `Node` class name through `engineClassName`, but it is a
plain struct to the hint resolver, so it gets no Node picker hint. Declare the
real object pointer type when the inspector picker is wanted.

### Signals

Signal argument types are declared Zig types, so the layer validates `.variant`
support when the `Signal` marker is declared, not when a signal is emitted. The
`Variant` argument is the one exception: it registers as untyped `.nil` and
emits its transparent storage. Registration derives each argument's Variant type
and engine class name from the same queries. `emit` converts through
`encodeVariant`; a custom converter argument must be an exact `T` value.

### Properties

The dynamic property backend validates every descriptor, including zero-usage
ones, with `checkSupported(T, .variant, ...)`. `.type` overrides only the
`PropertyInfo` type; it never bypasses conversion and never changes how the value
is encoded or decoded. `Variant` is convertible but has no Variant type, so
`Property(Variant)` needs an explicit `.type`; a type without `.variant` support
fails the check regardless of `.type`.

### Virtuals

Virtual registration validates `.ptr` support for every non-self parameter and
for a non-void return, then the callback uses `decodePtr`/`encodePtr`. Virtuals
have no Variant path and do not consult `.variant` support. A converter whose
engine type is a `RefCounted` pointer follows the same `Ref<T>` rule as a direct
`RefCounted` pointer.

## Examples

```zig
const Duration = struct {
    millis: i32,

    pub const GodotConversion = godot.annotations.Conversion(.{
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

`support(Duration)` is `.{ .variant = true, .ptr = true }`, `engineType` is
`i32`, `variantType` is `.int`, and `engineClassName` is empty. It works as a
property value and as a signal argument with no further declarations:

```zig
duration: godot.annotations.Property(Duration, .{ .usage = .exported }) = .init(.{ .millis = 0 }),

pub const DurationChanged = godot.annotations.Signal("duration_changed", .{
    .{ "duration", Duration },
});
```

```zig
const NodeRef = struct {
    node: ?*godot.classes.core.Node,

    pub const GodotConversion = godot.annotations.Conversion(.{
        .engine = ?*godot.classes.core.Node,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: NodeRef) ?*godot.classes.core.Node {
        return self.node;
    }

    fn fromEngine(node: ?*godot.classes.core.Node) NodeRef {
        return .{ .node = node };
    }
};
```

`support(NodeRef)` is both paths, `engineType` is `?*Node`, and
`variantType` is `.object`. Signals and properties deriving their metadata from
conversion report `engineClassName(NodeRef) == "Node"`. Emit and property get
copy the pointer into the Variant (engine ownership rules apply); `fromEngine`
receives a borrowed pointer on decode.

## Not in this version

- No conversion chains: an engine type must have direct support.
- No per-class or per-consumer conversion overrides; one marker per type.
- No conversion for `void`, integers wider than 64 bits, many-pointers, slices,
  or plain structs without a marker.
- No callables integration yet: `callable.zig` still uses
  `Variant.initDeclared`/`asDeclared` directly, so a custom converter is not
  accepted there. See [callables.md](callables.md).
- No methods or container conversion; both are planned consumers.

## Related

- [variants.md](variants.md) - the hand-written Variant payload, declared-type
  operations, and ownership.
- [annotations.md](annotations.md#conversionspec) - the `Conversion` marker
  declaration surface.
- [properties.md](properties.md#ownership-modes) - property set/deinit modes.
- [signals.md](signals.md#registration) - signal registration and emit.
- [virtuals.md](virtuals.md#refcounted-is-the-exception) - ptrcall/RefCounted
  callback behavior.
- [ownership.md](ownership.md) - borrowed arguments, transferred returns, and
  the retain/release helpers.
