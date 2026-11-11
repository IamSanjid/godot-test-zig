# ABI and conversion rules

This is the contract both backends follow. The goal is Godot GDExtension ABI
compatibility first, then the codegen-facing convenience types.

## Primitive mapping

| Godot API type | Binding Zig type | Codegen Zig type |
|---|---|---|
| `int` | `i64` | `i64` |
| `float` | `f32` / `f64` by `builtin_build_conf` | same |
| `bool` | `bool` | `bool` |
| `void`, `Nil` | `void` | `void` |
| `Variant` | `bindings.builtins.Variant` | `builtins.Variant` |
| class pointer | `?*BindingClass` return, `*BindingClass` arg | `?*Class` return, `*Class` arg |
| builtin | binding builtin extern struct | codegen builtin extern struct |
| normal enum | binding enum alias | codegen/binding enum alias |
| bitfield | packed struct with `u32` or `u64` backing | same alias |
| native struct | `bindings.native.X` | `native.X` alias |
| `Object` | class pointer | class pointer |
| `typedarray::T` | `Array` | `Array` |
| `typeddictionary::K,V` | `Dictionary` | `Dictionary` |

`real_t` comes from `builtin_build_conf`:

- `float_32`, `float_64` -> `f32`
- `double_32`, `double_64` -> `f64`

## Ptrcall argument slots

Class methods use `object_method_bind_ptrcall`. Builtin methods use
`PtrBuiltInMethod`.

| Argument kind | What is passed in `ConstTypePtr` |
|---|---|
| primitive/builtin value | pointer to the value |
| class pointer | pointer to the class pointer (pointer-to-pointer) |
| normal enum | pointer to an `i64` backing slot |
| bitfield | pointer to a `u32`/`u64` backing slot |
| `Variant` | pointer to the Variant value |
| `Object` inside a builtin method | pointer-to-pointer |

The backing width for a bitfield is derived from the highest used bit, not from
the current JSON version. `templates` and `enum_emit` use the same width rule.

Normal enums are still passed in `i64` slots. That is the current GDExtension
ptrcall assumption. Recheck this if Godot ever defines enum arguments with a
different ptrcall width.

## Return values

- Class pointer returns are optional `?*Class`.
- Builtin returns are values.
- `Variant` returns are initialized with `.nil()` before the engine call.
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
- enums/native/primitive -> direct

## Optional arguments and defaults

Bindgen reconstructs default arguments into local `actual_*` values, then passes
their addresses. Codegen does not reconstruct defaults: it passes an options
struct whose `toBinding()` produces the binding options struct, and the binding
method applies the defaults.

Default ownership:

- `String` / `StringName` literals use cached `fromComptimeLatin1`; do not
  deinitialize the returned copy.
- Empty `String()` / `StringName()` use `.init(dispatcher)` and are
  deinitialized.
- `NodePath`, `Array`, `Dictionary`, `Callable`, `Signal`, packed arrays, and
  typed containers are deinitialized after the binding call when generated from
  a default.
- `Variant` defaults use `.nil()` and need no deinit.

`String` and `NodePath` string literals are built from
`String.fromComptimeLatin1`. Non-empty `NodePath` does:

```zig
NodePath.fromString(dispatcher, String.fromComptimeLatin1(dispatcher, "..."))
```

## Variant object access

A class returned inside a `Variant` is not automatically downcast:

```zig
const object = variant.asObject(); // *Object
const node: *Node = @ptrCast(object);
```

`asObject`, `asCallable`, `asInt` exist in both binding and codegen Variant
implementations. No subclass inference is possible from the ABI; the caller is
responsible for using the correct class type.

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
`error.UnsupportedVarargReturn` instead of emitting a broken fallback.
