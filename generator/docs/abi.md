# ABI and conversion rules

This is the contract both backends follow. The goal is Godot GDExtension ABI
compatibility first, then the codegen-facing convenience types.

## Primitive mapping

| Godot API type | Public binding/codegen type | Ptrcall slot |
|---|---|---|
| `int` | per `meta`: `i8`/`u8`/`i16`/`u16`/`i32`/`u32`/`i64`/`u64`/`u32` (`char32`); no meta -> `i64` | `i64`, except `meta:"uint64"` -> `u64` |
| `float` (`meta` absent/`float`) | `real_t` (`f32`/`f64` by `builtin_build_conf`) | `f64` |
| utility `float` | `f64` | `f64` |
| `float` (`meta:"double"`) | `f64` | `f64` |
| `bool` | `bool` | `u8` |
| `void`, `Nil` | `void` | none |
| normal enum | binding enum alias | `i64` |
| bitfield | bitpack struct | `i64` |
| `Variant` | binding/codegen Variant | pointer to the value |
| class pointer | `?*Class` return, `*Class` arg | pointer-to-pointer |
| builtin | binding/codegen builtin extern struct | pointer to the value |
| native struct | `bindings.native.X` / `native.X` | pointer to the value |
| `Object` | class pointer | pointer-to-pointer |

`real_t` comes from `builtin_build_conf`:

- `float_32`, `float_64` -> `f32`
- `double_32`, `double_64` -> `f64`

`real_t` selects public float precision and builtin struct layout. It does not
select the ptrcall slot width. A public `f32` float is converted to an `f64` slot
at the binding boundary; `meta:"double"` is a public `f64`.

Builtin struct members use the selected configuration's `meta` spelling
directly: `meta:"float"` is always C++ `float` (`f32`) and `meta:"double"` is
always C++ `double` (`f64`). `real_t` members are emitted as `float` in
single-precision configurations and `double` in double-precision ones. Fixed
C++ floats such as `Color` stay `meta:"float"`/`f32` in both.

Utility functions are C++ `double` operations. Their public `float` signatures
use `f64` in both backends, regardless of `builtin_build_conf`.

## Ptrcall argument slots

Class methods use `object_method_bind_ptrcall`. Builtin methods use
`PtrBuiltInMethod`.

| Argument kind | What is passed in `ConstTypePtr` |
|---|---|
| `int` | pointer to an `i64`, except `meta:"uint64"` -> `u64` |
| `float` / `double` | pointer to an `f64` |
| `bool` | pointer to a `u8` (`0`/`1`) |
| normal enum | pointer to an `i64` backing slot |
| bitfield | pointer to a canonical `i64` slot |
| builtin value | pointer to the builtin value |
| class pointer | pointer to the class pointer (pointer-to-pointer) |
| `RefCounted` in a virtual | `Ref<T>` storage, not a raw object pointer |
| `Variant` | pointer to the Variant value |

Canonical slot width is independent of `builtin_build_conf`. Normal enums use an
`i64` slot. Packed bitfields use the canonical `i64` slot regardless of their
public 32/64-bit backing width.

Runtime code uses the same rule from `src/godot/abi.zig`:
`readArgument` / `writeReturn` marshal a value from its Zig type. Generated
bindings keep their own inline conversions so bindings stay independent of the
runtime layer.

## Return values

- Class pointer returns are optional `?*Class`.
- Builtin returns are values.
- `Variant` returns are initialized with `.nil` before the engine call.
- Constructors leave the destination `undefined` because the engine constructor
  initializes it.
- Non-trivial returned builtins (`String`, `StringName`, `NodePath`, `Array`,
  `Dictionary`, `Callable`, `Signal`, packed arrays) are initialized with
  `.init(dispatcher)` before the engine call.
- Primitive, POD builtin, pointer and enum results stay `undefined` until the
  engine writes them.

Codegen converts returns at the binding boundary:

- class pointer -> conditional `@ptrCast`
- builtin -> `fromBinding`
- `Variant` -> `Variant.fromBinding`
- float return -> `f64` slot converted to public `f32`/`f64`
- bool return -> `u8` slot converted to `bool`
- ints -> canonical slot; narrow public ints use `@intCast` and `uint64` uses the `u64` slot
- enums/native -> direct

## Optional arguments and defaults

Defaults that are compile-time values are stored directly in the options struct
as non-optional fields: primitives, enums, bitfields, `Color`, `Vector2`/`2i`,
`Vector3`/`3i`, `Vector4`/`4i`, `Rect2`, and `Rect2i`.

Bindgen then uses `opt.field` in place instead of reconstructing an `actual_*`
copy. Enum and bitfield fields are still converted to their ptrcall slots.

Codegen keeps the same options shape and its `toBinding()` assigns those fields
directly, calling `toBinding()` only for builtin values such as Color/Vector/Rect.

Runtime-owned defaults (`String`, `StringName`, `NodePath`, `Array`,
`Dictionary`, `Callable`, `Signal`, packed arrays, `Variant`, `RID`, class/native
pointers) remain optional and are reconstructed by bindgen when needed.

`Transform2D`/`Transform3D` defaults also remain optional. Their layouts are
ABI-correct, but binding-facing fields (`x`/`y`/`origin`, `Basis.x/y/z`) and
hand-written storage fields (`columns`, `Basis.rows`) are not spelled the same.

Default ownership:

- `String` / `StringName` / `NodePath` literals use cached `fromComptimeLatin1`
  values and must not be deinitialized.
- Empty `String()`, `StringName()`, and `NodePath()` also use cached
  `fromComptimeLatin1` values and must not be deinitialized.
- `Array`, `Dictionary`, `Callable`, `Signal`, packed arrays, and typed
  containers are deinitialized after the binding call **only when bindgen
  constructed the default itself**.
- Caller-provided option values remain caller-owned; generated bindings do not
  deinitialize them.
- `Variant` defaults use `.nil` and need no deinit.

`String` has no static-buffer constructor, so `String.fromComptimeLatin1` copies
once and caches the result for the process lifetime. `StringName` uses
`is_static = true` and reuses the literal buffer. `NodePath` has no static
constructor either, so `NodePath.fromComptimeLatin1` constructs one NodePath per
unique literal and caches it for the process lifetime. Its temporary
`String.fromLatin1` input is deinitialized immediately after construction because
NodePath copies the parsed contents.

`String.fromLatin1` is the owned runtime constructor for dynamic Latin-1 data.
Cached values are intentionally never deinitialized.

`String` and `NodePath` string literals are built from the cached constructors:

```zig
String.fromComptimeLatin1(dispatcher, "...")
NodePath.fromComptimeLatin1(dispatcher, "...")
```

These caches are lazy process-lifetime globals and are not synchronized. Like
the existing `StringName` cache, initialize them on a single thread before
sharing them across threads.

Returned `String`/`NodePath` values from engine calls are owned by the caller and
still require deinit when the caller is done with them.

## Variant object access

A class returned inside a `Variant` is not automatically downcast:

```zig
const object = variant.as(*Object) orelse return null; // borrowed *Object
const node: *Node = @ptrCast(object);
```

Typed extraction is `Variant.as(T)` / `Variant.as(*T)` on the hand-written
codegen Variant: it returns `null` on a tag mismatch and performs no conversion.
The raw binding Variant keeps internal `asInt`/`asCallable` accessors for
generated vararg returns. No subclass inference is possible from the ABI; the
caller is responsible for using the correct class type.

## Virtual methods

- Required virtuals are metadata only; no convenience wrapper is generated.
- Optional virtuals get wrappers.
- Inherited optional virtuals are forwarded through the binding class to its
  parent wrapper.
- Virtual `self` follows `method.is_const`.
- Registration callback casting belongs to the library layer, not codegen.

## Varargs

Converting arbitrary Zig values into Variants is a library/caller concern. A
library utility produces a tuple/array of codegen Variants; the generated codegen
wrapper then converts each element into the binding Variant stack array:

```zig
var args: [vargs.len]bindings.builtins.Variant = undefined;
inline for (vargs, 0..) |value, i| {
    if (@TypeOf(value) != builtins.Variant) {
        @compileError("vargs: should only contain 'Variant' types.");
    }
    args[i] = value.toBinding();
}
```

This applies to class, generated-builtin, and utility varargs.

Bindgen wrappers build the final engine pointer array from:

- fixed typed arguments converted to binding Variants, plus
- the codegen-converted binding Variant `vargs`

Unsupported vararg return types now fail generation with
`error.UnsupportedVarargReturn` instead of emitting a broken fallback. Fixed
argument types are validated against the raw Variant.wrap subset up front, so an
unsupported future API type fails generation with
`error.UnsupportedVarargFixedArgument` rather than a lazy compile error.
