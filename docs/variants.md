# Variant conversion

The hand-written `Variant` layer is the bridge between Zig values and Godot's
`Variant`. It is separate from generated bindings and from ptrcall marshalling.

## API

```zig
Variant.wrap(T, value)   // borrowed view
Variant.init(T, value)   // owned Variant
Variant.as(T)            // typed extraction
Variant.clone()          // owning shallow copy
Variant.deinit()         // destroy an owning Variant
Variant.typeFor(T)       // VariantType or null
```

There are no per-type convenience accessors (`asInt`, `asObject`, ...):
`as(T)` / `as(*T)` is the single typed-extraction entry point, and its optional
return makes a tag mismatch explicit.

`fromPtr` is removed. `wrap` is the replacement, because the old name implied a
construction/ownership that never happened.

The generated raw bindings also expose a layer-specific helper:

```zig
bindings.builtins.Variant.wrap(dispatcher, T, value)
```

It has the same borrowed contract but takes `dispatcher` for object instance
ids and supports only the fixed-argument types generated call sites need.
Generated vararg code uses it; it is not the user-facing codegen API.

## Ownership

`wrap`:

- borrows pointer/engine-managed payloads; inline scalar and plain-value
  builtins are copied into the Variant payload
- performs no engine allocation
- changes no reference counts
- must never be passed to `deinit`
- is valid only while the source value is alive
- rejects packed arrays
- rejects builtins the engine stores behind an owned heap allocation
  (`AABB`, `Basis`, `Projection`, `Transform2D`, `Transform3D`)

Use `init` for those types.

`init`:

- returns an owning Variant
- copies non-trivial builtins through the engine Variant constructors; object
  data is constructed explicitly (see the object rules below)
- leaves the input argument owned by the caller
- for packed arrays, lets the engine create the copy-on-write packed-array ref
- for `RefCounted` object pointers, takes one owning reference through the
  ClassDB `reference` path; `deinit` releases it. RefCounted-ness is read from
  the runtime engine instance ID, so an upcast `*Object` that points at a
  `RefCounted` is handled
- for non-`RefCounted` object pointers, stores a borrowed object reference
- for extension class pointers, resolves the ultimate engine base object through
  the `Base` marker chain and applies the rules above to that engine object; the
  Zig instance itself is not stored (the engine object owns it)

`as`:

- returns `null` on an exact tag mismatch; no implicit Variant conversion
- integer, enum and bitfield targets also return `null` when the Variant `i64`
  payload is out of range for the requested type; exhaustive enums also reject
  payloads that are not declared members. Unsigned 64-bit targets are
  bit-preserving
- scalars and plain value builtins are returned by value
- `String`, `StringName`, `NodePath`, `Callable`, `Signal`, `Array`,
  `Dictionary`, and packed arrays are returned owned; deinit them
- object pointers are borrowed from the Variant. The object tag is checked, but
  the runtime class and object lifetime are not; the Variant must hold a live
  object of the requested class
- extension class pointers resolve the stored engine base object and return the
  registered Zig instance through that base's `asInstance(Extension)`; the
  instance is borrowed and `null` means no matching instance binding
- pass non-optional object pointers (`as(*Node)`, not `as(?*Node)`)

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
u64-backed values bit-cast), floats to `data.float`.

Variant from-type and to-type constructors are resolved lazily once per
`VariantType` and cached for the dispatcher lifetime; this is a first-use
optimization, not part of the conversion contract.

## Variant layout

A Variant is **24 bytes** when `real_t` is `f32` and **40 bytes** when `real_t`
is `f64`. That size comes from `_mem[sizeof(real_t) * 4]` and the generated
builtin member sizes, not from the `float` payload. The `float` field stays
`f64` in both layouts.

The generated binding Variant takes its opaque size and `checkTypeLayout`
expectation from the selected `--builtin-build-conf`. Bindgen emits a 40-byte
Variant for `double_64` and a 24-byte Variant for `float_64`.

The codegen builtins select their single/double aliases from
`bindings.is_double_precision`, which is derived from the generated Variant
size. Both configurations build; `float_64` is the default. Do not infer
Variant size from `Data.float`.

## Type mapping

`Variant.typeFor(T)` is hand-written and covers:

- codegen builtin types
- engine object class pointers and Zig extension class pointers (including
  optional pointers) -> `object`
- bool, ints, floats
- enums and packed bitfields
- `Variant` itself (`null`, transparent storage)

It only reports the Variant type. Per-class object metadata (class name,
properties) is a future property-layer concern and is not built here.

Codegen builtins bridge through `toBinding` / `fromBinding`. Generated bindings
are not used as public property/user types.

## Current limits

- `float_64` is the default. `double_64` is supported by the generators and the
  codegen layout, but the example and tests primarily run the default.
- Extension -> extension class registration remains unavailable; see
  [Chain limitation](#chain-limitation).
- `as(*Extension)` only returns instances attached by runtime registration; a
  Variant holding a plain engine object has no Zig instance to return.
