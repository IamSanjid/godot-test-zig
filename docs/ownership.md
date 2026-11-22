# Ownership and lifetime

This documents the intended ownership contract for hand-written runtime code and
virtual callbacks. It does not replace the generated ABI documentation in
`generator/docs/abi.md`.

## Virtual arguments

Virtual arguments are **borrowed**.

- The engine owns the argument storage.
- The virtual callback must not deinitialize arguments.
- For `Variant`, `String`, `Array`, `Dictionary`, `Callable`, `Signal`, packed
  arrays, and other non-trivial builtins, a value copy is a borrowed view.
- If the user stores an argument or returns it, they must obtain an owned
  copy/reference first.

`toBinding` / `fromBinding` are bitcasts. They do not increment reference counts
and do not turn a borrowed value into an owned one.

## Virtual returns

Virtual return values are **transferred to the engine**.

- Write the returned value into `r_ret`.
- Do not deinitialize the returned value afterwards.
- Return an owned value. Do not return a borrowed argument directly unless the
  type has value semantics and no internal references.
- For `Variant` and non-trivial builtins, returning a borrowed argument can
  double-own internal references.

## Object pointers

### Ordinary `Object` subclasses

Non-`RefCounted` object arguments are passed as `Object**`; returns are `Object*`.

- Direct pointer casting is correct.
- The engine owns object lifetime; the callback must not destroy the object.
- The user must not free an object they did not own.

### `RefCounted`

`RefCounted` virtual arguments and returns use `Ref<T>` storage:

- argument: `p_args[i]` points to `Ref<T>`; use `ref_get_object`
- return: `r_ret` points to `Ref<T>`; use `ref_set_object`

The object pointer returned by `ref_get_object` is borrowed for the call.
If the user retains it, they must take their own reference.

`ref_set_object` writes the returned object into the engine-owned `Ref<T>`
storage and **adds a new owning reference** there. That reference belongs to the
engine storage; it is not a borrow. If the user owns another reference to the
object, they must release their own reference separately; do not assume the
callback consumes it.

Do not assign a raw pointer into `Ref<T>` storage.

## `Variant`

Variant arguments are borrowed Variant views. If the user keeps or returns one,
the Variant must be copied with the appropriate engine copy/duplicate operation.

Variant returns are moved into `r_ret`. The user must construct an owned
Variant. Returning an argument Variant directly is unsafe without cloning.

Variant ownership and conversion are documented in
[variants.md](variants.md). In short: `wrap` is borrowed, `init` is owning,
`as` has typed extraction ownership rules, and `clone`/`deinit` manage owning
Variants.

## Builtins and codegen types

Codegen builtin types are ABI-compatible wrappers:

- `toBinding` / `fromBinding` are bitcasts
- sizes, alignments, and offsets are checked by generated code where applicable
- hand-written builtins are explicitly ABI-compatible

Scalar ptrcall slots are canonical and independent of builtin precision:

- API `float` / `real_t` -> `f64` slot
- integers, enums and packed flag structs -> canonical `i64` slot (`u64` only for plain u64 integers)
- `bool` -> `u8` slot

Public signatures may still use `real_t` for class/builtin API floats (for
example `f32`), and API `int` metadata selects the public integer width
(`int8`, `uint32`, `uint64`, `char32`, ...). The generator owns that
API-metadata-to-public-type mapping; `godot.abi` only classifies the resulting
Zig types and converts at the ptrcall boundary. Utility `float` signatures are
public `f64` because the engine utility implementation is C++ `double`.

Virtual callbacks use the codegen type directly for builtins and object shapes.
This is valid only while the ABI-compatibility invariant holds. If a codegen
builtin ever diverges from its binding layout, virtual marshalling must gain a
conversion step.

## Binding returns

Class-pointer returns from generated bindings:

- Non-`RefCounted` class pointers are borrowed engine pointers.
- `RefCounted` class-pointer returns are written by the engine into an
  initialized empty `Ref<T>` slot and carry **one owning reference**. The raw
  pointer returned by the binding represents that reference. Release it with
  `unreference` when done unless you transfer it to another owner.
- The binding initializes the return storage to `null` first. Do not remove that
  initialization: Godot's ptrcall encode assigns into a real `Ref<T>`, and an
  undefined slot would unref garbage.

## Return storage

`r_ret` points to the return temp created by Godot's virtual thunk. That temp is
default-constructed immediately before the extension callback, so it does not
contain a previous non-empty value; the callback writes the new value directly.
Do not deinitialize `r_ret` contents after writing.

This matches Godot's virtual callback convention: return storage is
default-constructed before the extension is called.
