# Variant conversion

The hand-written `Variant` layer is the bridge between Zig values and Godot's
`Variant`. It is separate from generated bindings and from ptrcall slot mapping.
It owns the payload, the declared-type `initDeclared`/`asDeclared` operations, and
their ownership rules; [conversion.md](conversion.md) owns the declared-type
support and metadata layer that properties, signals, and virtuals use. Engine
object ownership outside the payload (`Ref` owns a reference, raw pointers are
borrowed) is stated once in [ownership.md](ownership.md).

## API

```zig
Variant.borrow(T, value) -> Variant.Borrowed  // view; accepts a raw value or pointer
Variant.canBorrow(T)                          // true when borrow can create a view
Variant.init(T, value)   // owned Variant
Variant.as(T)            // typed extraction
Variant.initDeclared(Declared, value)  // owned Variant for a declared type
Variant.asDeclared(Declared)           // declared-type extraction
Variant.clone()          // owning shallow copy
Variant.deinit()         // destroy an owning Variant
Variant.objectInstance() // validated live object pointer or null
Variant.isNullObject()   // true for engine OBJECT-null payload
Variant.typeFor(T)       // VariantType or null
```

The hand-written Variant has no per-type convenience accessors (`asInt`,
`asObject`, ...): `as(T)` / `as(*T)` is the single exact typed-extraction entry
point, its optional return makes a tag mismatch explicit, and `asDeclared(T)` is
the declared-type form described below.

A `Variant.Borrowed` is a non-owning view. `inner` is the borrowed `Variant`
alias, `get()` returns a shallow copy of it (24 bytes in the default layout) so
`Variant.borrow(T, value).get()` can be passed directly to a Variant-taking call,
and `getPtrConst()` returns a `*const Variant` valid only while the view lives.
The view has no `deinit`, `clone`, or mutable accessor: destroying or mutating
borrowed storage is never valid.

## Conversion layer

Declared surfaces ([`Property`](properties.md), [`Signal`](signals.md), and
virtuals/methods) use an internal declared-type conversion layer over these
operations. User code does not call it: it declares a supported type or a
`Conversion` marker and the surface handles the rest. The model is in
[conversion.md](conversion.md). For this page, the layer:

- classifies declared types as directly supported (scalars, enums, builtins,
  object pointers, and raw single-item pointers, which are ptrcall-only), or
  represented by the marker's directly supported engine type; conversion never
  chains.
- composes the Variant-path operations on this page: a converted type is decoded
  as `asDeclared(Engine)` followed by `from_engine`, and encoded as `to_engine`
  followed by `initDeclared(Engine)`.
- uses a separate ptrcall path for virtuals and planned methods; that path
  carries no Variant.

`Variant.typeFor(T)` reports only a direct representation. A declared surface
follows a `Conversion` marker through the internal layer, so use the Variant
methods below when working with a Variant directly, and
`Variant.asDeclared(Engine)` plus the marker's `fromEngine` when receiving a
converter value outside a declared surface.

## Declared-type conversions

`init` and `as` are exact: the Zig type must equal the declared type, and `as`
does no runtime class check. Annotation surfaces and registration know a
*declared* engine type and let callers pass any value that is correctly
representable in it, so two operations sit on top:

| Declared type | `initDeclared` accepts | `asDeclared` returns |
|---|---|---|
| scalar, enum, bitfield, builtin | the exact type; numeric literals coerce, and enum literals coerce to enums | the value, or null on a tag/range mismatch |
| `Variant` | a `Variant`, cloned | a clone |
| `?*EngineClass` / `*EngineClass` | `null` (optional only), an engine class pointer that extends it, or an extension instance whose engine base extends it | a borrowed pointer after `Object.isClass` accepts it (subclasses pass) |
| `?*ExtensionClass` / `*ExtensionClass` | `null` (optional only), or exactly that extension instance | the registered instance, or null |

- Extension instances are never engine pointers: reduction walks
  `reflect.engineBasePointer` through the `Base(direct parent)` marker at every
  level. A missing marker, or a declared class outside the value's engine base
  chain, is a compile error.
- Engine subclass pointers are accepted and pointer-cast to the declared class;
  Godot's single inheritance puts the base at offset zero, the same assumption
  the generated bindings and `as` already rely on.
- Extension-declared types are exact-class. The instance binding is per class,
  so only that instance is accepted and only it resolves back.
- `asDeclared` returns `?Declared`, so a mismatch cannot be told apart from a
  null value by the outer optional alone: for an optional declared type the
  result is doubly optional (`??*T`) - the outer null is a mismatch, the inner
  null is a `nil` value.
- The declared forms follow the same ownership rules as `init`/`as` below:
  `initDeclared` returns an owning Variant, `asDeclared` borrows object pointers
  and returns owned builtins.

The generated raw bindings expose a separate layer helper:

```zig
bindings.builtins.Variant.borrow(dispatcher, T, value) -> bindings.builtins.Variant
```

It is not the public `Variant.Borrowed` view: it returns a raw binding `Variant`
and takes `dispatcher` for object instance ids. It accepts pointer arguments only
(`*T`, `*const T`, `?*T`, `?*const T`) for every inline builtin, class pointer,
scalar, enum, and bitfield, and rejects packed arrays and heap-backed builtins.
The raw-value `borrow` forms described below belong to the hand-written
`Variant`; this bindgen-layer helper stays pointer-based. Generated vararg code
uses it; it is not the user-facing codegen API.

## Ownership

`borrow` accepts either a pointer or, where safe, a raw value, and returns a
`Variant.Borrowed`. The view owns nothing and is call-scoped: the borrowed
payload is valid only while the source value is alive, and the view is never
stored.

```zig
const scalar = Variant.borrow(i32, @as(i32, 42));
const point = Variant.borrow(Vector2, Vector2.zero);
const node_view = Variant.borrow(*Node, node);        // borrowed pointer
const nil_view = Variant.borrow(?*Node, null);
const name_view = Variant.borrow(StringName, &name); // borrowed pointer
const raw = Variant.borrow(i32, 7).get();            // copy for a Variant-taking call
```

- raw scalars, enums, packed bitfields, and inline plain-value builtins are
  copied into the Variant payload; they have no source lifetime
- untyped literals are accepted when the target type is unambiguous:
  `Variant.borrow(i32, 7)`, `Variant.borrow(?*Node, null)`,
  `Variant.borrow(Mode, .b)`
- raw object pointers are borrowed exactly like the pointer form
- pointer forms borrow the pointed payload
- performs no engine allocation
- changes no reference counts
- rejects packed arrays (`PackedByteArray`, ...), including raw values
- rejects builtins the engine stores behind an owned heap allocation
  (`AABB`, `Basis`, `Projection`, `Transform2D`, `Transform3D`)
- owned deinit-types (`String`, `StringName`, `NodePath`, `Callable`, `Signal`,
  `Array`, `Dictionary`) are inline in Variant storage but own an internal
  refcounted buffer; they must be passed by pointer to be borrowed so the source
  lifetime is explicit. A raw value
  is rejected because copying it would alias engine-owned storage

Use `init` for packed arrays, heap-backed builtins, and owned raw deinit-types.
Those are value types in Zig, but their Variant representation is an engine-owned
allocation or refcounted header, so a borrowed view of a raw value is not
possible.

`Variant.canBorrow(T)` is the classification behind `borrow`: true for canonical
scalars, `Variant`, inline builtins (plain or managed), and object pointers;
false for packed arrays, heap-backed builtins, raw non-object pointers, and
classes. A declared surface uses the internal conversion layer to decide whether
it can pass a borrowed view to a synchronous engine call such as signal emit, and
to write that view.

`init`:

- returns an owning Variant and accepts a raw value for every supported type,
  including `Transform2D`, `Transform3D`, `PackedArray`, and other types that
  `borrow` rejects
- copies non-trivial builtins through the engine Variant constructors; object
  data is constructed explicitly (see the object rules below)
- leaves the input argument owned by the caller
- for packed arrays, lets the engine create the copy-on-write packed-array ref
- for `RefCounted` object pointers, takes one owning reference through the
  ClassDB `reference` path; `deinit` releases it. RefCounted-ness is read from
  the runtime engine instance ID, so an upcast `*Object` that points at a
  `RefCounted` is handled. This adds a reference rather than consuming a
  creation reference: a pointer moved out of a typed handle with `.take()` (or a
  raw binding constructor result) still carries that reference, so the caller
  must release it separately; keep the `Ref` handle instead when it should own
  the object. See [ownership.md](ownership.md#construction)
- for non-`RefCounted` object pointers, stores a borrowed object reference
- for extension class pointers, resolves the ultimate engine base object through
  the `Base` marker chain and applies the rules above to that engine object; the
  Zig instance itself is not stored (the engine object owns it)

An owning Variant is the only object-owning form: its payload holds one
reference to a stored `RefCounted` object and releases it on `deinit`. A
borrowed object view from `borrow` holds the object id/pointer only, owns no
reference, and must never be deinitialized. A pointer read from an owning
Variant is borrowed while that Variant stays alive.

`as`:

- returns a raw value already; no wrapping step is needed
- returns `null` on an exact tag mismatch; no implicit Variant conversion
- integer, enum and bitfield targets also return `null` when the Variant `i64`
  payload is out of range for the requested type; exhaustive enums also reject
  payloads that are not declared members. Unsigned 64-bit targets are
  bit-preserving
- scalars and plain value builtins are returned by value
- `String`, `StringName`, `NodePath`, `Callable`, `Signal`, `Array`,
  `Dictionary`, and packed arrays are returned owned; deinit them
- object pointers are borrowed from the Variant. `as` validates the stored
  instance id against ObjectDB and returns `null` for a stale or null object;
  the declared runtime class is not checked, so a live object of the wrong class
  can still be returned
- extension class pointers resolve the stored engine base object and return the
  registered Zig instance through that base's `asInstance(Extension)`; the
  instance is borrowed and `null` means no matching instance binding
- pass non-optional object pointers (`as(*Node)`, not `as(?*Node)`)

`objectInstance()` is the validated object read: it checks the object tag, the
stored instance id, and the ObjectDB lookup before returning a pointer. It is
separate from `as(*C)`, which now also uses the same validation before returning
the object pointer. Engine null objects (`OBJECT` tag with empty ObjData) return
`null`; `isNullObject()` exposes that state. `borrow`/`init` of a typed null
optional object currently produce `Variant.nil`, so both null representations
must be accepted by callers.

`clone` uses `variant_new_copy`: shallow Variant copy, but the copy owns its own
references. It is also how a borrowed view becomes owning:
`Variant.borrow(T, ptr).get().clone()`.

`deinit` is only for owning Variants. Do not call it on `Variant.borrow` results
or borrowed Variant arguments.

## Extension classes

A Variant object can only store an **engine object**; a Zig extension instance is
owned by its engine base. The conversion helpers translate between extension
instances and that engine base:

- `borrow(Extension, ptr)` resolves the ultimate engine base through the class's
  `Base` marker chain and creates the same borrowed object Variant as for an
  engine class pointer. The Zig instance is not stored in the Variant; the
  instance and its engine base must outlive the view.
- `init(*Extension, ptr)` resolves the engine base and constructs the Variant with
  that base's ownership rules (an owning `RefCounted` reference when the base is
  RefCounted). Keeping the engine base alive also keeps the extension instance
  alive, because the engine object owns it.
- `as(*Extension)` recovers the engine base object from the Variant and calls
  `EngineBaseType(Extension).asInstance(Extension)` to return the registered Zig
  instance. The pointer is borrowed and valid while the engine object exists;
  `null` means the Variant does not hold an object with a binding for that exact
  extension class (for example a plain engine object).
- `typeFor(*Extension)` / `typeFor(?*Extension)` report `object`.

Every extension level must declare a Base marker for its direct parent, normally
`base: annotations.Base(Extends) = .{}`. `reflect.EngineBaseType` /
`engineBasePointer` enforce that; a missing marker is a compile error naming the
class and parent. The marker must be initialized; registration does that. A
manually allocated extension instance with an uninitialized marker is outside
the supported conversion contract: safe builds assert in the marker guard,
ReleaseFast is undefined behavior.

### Chain limitation

Godot 4 does not implement registering an extension class that inherits
another extension class. Runtime registration is therefore scoped to a
**direct extension class over an engine class**. The
conversion helpers can still traverse a manually established
extension -> extension chain when its Base markers and instance bindings exist,
but such a chain cannot be registered by the current runtime (the Registry has a
guard for this).

## Packed arrays

Packed-array Variant storage is an engine-private refcounted header. Its C++
layout is not modelled: `*PackedArrayRef(T)` is an opaque pointer, not a Zig
struct. We never construct, mutate, dereference, or reason about the header
layout manually.

Rules:

- `borrow(PackedByteArray, ...)` is a compile error.
- `init` and `as` go through the engine Variant constructors.
- `init` is the minimum required engine-side copy; `as` returns the engine's
  normal copy-on-write packed-array value.
- Never deep-copy packed arrays on our side.

Each generated packed-array type also exposes zero-copy element views:
`asSlice()` returns a mutable `[]T` view and forces a copy-on-write detach, while
`asSliceConst()` returns a read-only `[]const T` view that is invalid after the
array is modified or freed. They are not called `slice` because the engine class
already has `slice(begin, end)`, which returns a new packed array; `asSlice` names
the borrowed element view instead.

## Typed containers

The `Array` and `Dictionary` builtins can carry engine-side element typing
metadata, set with the generated `setTyped`/`setTypedAs` container methods;
`godot.collections` does this when it creates a wrapper. This is container state,
not Variant metadata:

- a Variant holding a typed container is still an ordinary `.array` or
  `.dictionary` Variant; `as`/`asDeclared` return the builtin handle unchanged
  and convert no elements;
- the `godot.collections` wrappers themselves are declared conversion types: a
  `Conversion` marker maps the wrapper to the engine `builtins.Array`/
  `builtins.Dictionary`, so a declared surface can carry a wrapper on both the
  Variant and ptrcall paths, and the wrapper composes element conversion
  lazily. The Variant payload is the ordinary container; typed container state
  travels with the handle;
- the Variant declared-type operations are not the entry point for a wrapper:
  `Variant.asDeclared(Wrapper)` and `Variant.initDeclared(Wrapper, ...)` do not
  accept the wrapper type, and `Variant.typeFor(Wrapper)` reports nothing.
  Use a declared `Property`/`Signal` surface for the wrapper; to read the
  decorated container's own type directly, use
  `as`/`asDeclared(builtins.Array)`/`(builtins.Dictionary)`;
- property hints for containers are separate metadata
  ([properties.md](properties.md#typed-container-hints)), and no Variant
  operation converts elements.

Wrapper ownership and element conversion are in
[collections.md](collections.md).

## Scalar storage

`abi.Box(T)` is the shared type-driven scalar mapping; there is no Slot enum.
Ptrcall slots use canonical widths (bool -> `u8`, ints/enums/bitfields -> `i64`,
float/double -> `f64`). The Variant payload follows the same classification, not
the slot widths: bool goes to `data.bool`, integers to `data.int` (`i64`, with
u64-backed values bit-cast), floats to `data.float`. Unsigned 64-bit integers
use a `u64` canonical ptrcall slot (`abi.Box(u64).Raw`), unlike narrower
unsigned integers which widen to `i64`; Variant payloads still store both as the
bit-preserving `i64` payload.

Conversion does not add a narrower float path. Both `f32` and `f64` are
canonical float types, so the ptrcall slot and the Variant `float` payload are
`f64` and narrow back with `@floatCast`. A converter's engine float type follows
the same rule; `real_t`/builtin layout configuration does not change the
payload width.

## Variant layout

A Variant is **24 bytes** when `real_t` is `f32` and **40 bytes** when `real_t`
is `f64`: 4-byte tag plus padding to offset 8, then
`max(sizeof(ObjData), sizeof(real_t) * 4)`. The `float` field stays `f64` in both
layouts. The data union is `alignas(8)` in every configuration, including 32-bit
targets.

The generated binding Variant owns the payload layout and `checkTypeLayout`
expectation; hand-written `Variant.Data` aliases it. Bindgen emits a 40-byte
Variant for `double_64` and a 24-byte Variant for `float_64`. Generated
`builtins/traits.zig` classifies builtins for both layers.

The codegen builtins select their single/double aliases from
`bindings.is_double_precision`, which is derived from the generated Variant
size. Both configurations build; `float_64` is the default. Do not infer
Variant size from `Data.float`.

## Type mapping

`Variant.typeFor(T)` is hand-written and covers:

- codegen builtin types
- engine object class pointers and Zig extension class pointers (including
  optional pointers) -> `object`
- bool, ints, floats narrower than or equal to 64 bits
- enums and packed bitfields up to 64 bits
- `Variant` itself (`null`, transparent storage)

Canonical scalars wider than 64 bits return `null`; they cannot fit the engine's
`i64`/`f64` payload and are rejected rather than mis-reported. It only reports
the Variant type; it does not carry per-class object metadata. A declared type
with a `Conversion` marker has no direct `Variant.typeFor` representation: a
declared surface derives the Variant type from the marker's engine type through
the internal conversion layer.

The engine-facing metadata used by properties and signals is derived the same
way from the declared type:

- the `PropertyInfo`/signal-argument Variant type follows a converter's engine
  type; the dynamic property backend uses it unless `.type` is set.
- the engine class name is the engine representation's class name, empty for
  non-object types. The property backend uses it for `class_name` when the
  descriptor's declared-type hint did not supply one, and signal registration
  uses it for every argument.

Enum/bitfield hints still come from the declared Zig type, not from the engine
representation; `Constants` adds the registered `<Class>.<Name>` class name and
typed-doc usage bits. See [properties.md](properties.md).

Codegen builtins bridge through `toBinding` / `fromBinding`. Generated bindings
are not used as public property/user types.

## Current limits

- `float_64` is the default. `double_64` is supported by the generators and the
  codegen layout, but the example and tests primarily run the default.
- Extension -> extension class registration remains unavailable; see
  [Chain limitation](#chain-limitation).
- `as(*Extension)` only returns instances attached by runtime registration; a
  Variant holding a plain engine object has no Zig instance to return.
