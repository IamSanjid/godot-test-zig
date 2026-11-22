# Variant conversion

The hand-written `Variant` layer is the bridge between Zig values and Godot's
`Variant`. It is separate from generated bindings and from ptrcall marshalling.

## API

```zig
Variant.wrap(T, value)   // borrowed view (raw or pointer)
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

`fromPtr` is removed. `wrap` is the replacement, because the old name implied a
construction/ownership that never happened.

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

The generated raw bindings also expose a layer-specific helper:

```zig
bindings.builtins.Variant.wrap(dispatcher, T, value)
```

It has the same borrowed contract but takes `dispatcher` for object instance
ids. It accepts pointer arguments for every inline builtin, class pointer,
scalar, enum and bitfield, and rejects packed arrays and heap-backed builtins.
The raw-value `wrap` forms described below belong to the hand-written `Variant`;
this generated-bindings helper remains pointer-based. Generated vararg code uses
it; it is not the user-facing codegen API.

## Ownership

`wrap` accepts either a pointer or, where safe, a raw value:

```zig
const scalar = Variant.wrap(i32, @as(i32, 42));
const point = Variant.wrap(Vector2, Vector2.zero);
const node_variant = Variant.wrap(*Node, node);       // borrowed pointer
const nil_variant = Variant.wrap(?*Node, null);
const borrowed = Variant.wrap(StringName, &name);     // borrowed pointer
```

- raw scalars, enums, packed bitfields, and inline plain-value builtins are
  copied into the Variant payload; they have no source lifetime
- untyped literals are accepted when the target type is unambiguous:
  `Variant.wrap(i32, 7)`, `Variant.wrap(?*Node, null)`,
  `Variant.wrap(Mode, .b)`
- raw object pointers are borrowed exactly like the pointer form
- pointer forms borrow the pointed payload
- performs no engine allocation
- changes no reference counts
- must never be passed to `deinit`
- a borrowed payload is valid only while the source value is alive
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
allocation or refcounted header, so a borrowed raw wrap is not possible.

`init`:

- returns an owning Variant and accepts a raw value for every supported type,
  including `Transform2D`, `Transform3D`, `PackedArray`, and other types that
  `wrap` rejects
- copies non-trivial builtins through the engine Variant constructors; object
  data is constructed explicitly (see the object rules below)
- leaves the input argument owned by the caller
- for packed arrays, lets the engine create the copy-on-write packed-array ref
- for `RefCounted` object pointers, takes one owning reference through the
  ClassDB `reference` path; `deinit` releases it. RefCounted-ness is read from
  the runtime engine instance ID, so an upcast `*Object` that points at a
  `RefCounted` is handled. This adds a reference rather than consuming a
  creation reference: if the pointer came from `construct()`/a fresh creation,
  the caller must claim or release that creation reference separately
- for non-`RefCounted` object pointers, stores a borrowed object reference
- for extension class pointers, resolves the ultimate engine base object through
  the `Base` marker chain and applies the rules above to that engine object; the
  Zig instance itself is not stored (the engine object owns it)

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
`null`; `isNullObject()` exposes that state. `wrap`/`init` of a typed null
optional object currently produce `Variant.nil`, so both null representations
must be accepted by callers.

`clone` uses `variant_new_copy`: shallow Variant copy, but the copy owns its own
references. It is also how a borrowed `wrap` becomes owning.

`deinit` is only for owning Variants. Do not call it on `wrap` results or
borrowed Variant arguments.

## Extension classes

A Variant object can only store an **engine object**; a Zig extension instance is
owned by its engine base. The conversion helpers translate between extension
instances and that engine base:

- `wrap(Extension, ptr)` resolves the ultimate engine base through the class's
  `Base` marker chain and creates the same borrowed object Variant as for an
  engine class pointer. The Zig instance is not stored in the Variant; the
  instance and its engine base must outlive the wrapped Variant, and the wrapped
  Variant must not be deinitialized.
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
another extension class: `gdextension.cpp` logs `ERR_PRINT("Unimplemented yet")`
when the parent class is registered by an extension. Runtime registration is
therefore scoped to a **direct extension class over an engine class**. The
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

- `wrap(PackedByteArray, ...)` is a compile error.
- `init` and `as` go through the engine Variant constructors.
- `init` is the minimum required engine-side copy; `as` returns the engine's
  normal copy-on-write packed-array value.
- Never deep-copy packed arrays on our side.

## Scalar storage

`abi.Box(T)` is the shared type-driven scalar mapping; there is no Slot enum.
Ptrcall slots use canonical widths (bool -> `u8`, ints/enums/bitfields -> `i64`,
float/double -> `f64`). The Variant payload follows the same classification, not
the slot widths: bool goes to `data.bool`, integers to `data.int` (`i64`, with
u64-backed values bit-cast), floats to `data.float`. Unsigned 64-bit integers
use a `u64` canonical ptrcall slot (`abi.Box(u64).Raw`), unlike narrower
unsigned integers which widen to `i64`; Variant payloads still store both as the
bit-preserving `i64` payload.

Variant from-type and to-type constructors are resolved lazily once per
`VariantType` and cached for the dispatcher lifetime; this is a first-use
optimization, not part of the conversion contract.

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
the Variant type; it does not carry per-class object metadata.
The dynamic property backend derives `PropertyInfo` type and class names from
`Variant.typeFor` plus `reflect.classNameOf`; see
[properties.md](properties.md).

Codegen builtins bridge through `toBinding` / `fromBinding`. Generated bindings
are not used as public property/user types.

## Current limits

- `float_64` is the default. `double_64` is supported by the generators and the
  codegen layout, but the example and tests primarily run the default.
- Extension -> extension class registration remains unavailable; see
  [Chain limitation](#chain-limitation).
- `as(*Extension)` only returns instances attached by runtime registration; a
  Variant holding a plain engine object has no Zig instance to return.
