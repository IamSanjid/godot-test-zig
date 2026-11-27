# Virtual methods

Virtual registration is metadata-driven. Users write normal Zig methods with the
generated virtual signature; [registration/virtuals.zig](../src/godot/registration/virtuals.zig)
supplies the C callback. No wrapper per virtual is required.

## Generated metadata

Codegen emits two signature groups plus metadata:

```zig
pub const Virtual = struct {
    pub const Required = struct {
        pub const _getWidth = *const fn (self: *const Texture2D) callconv(.c) i32;
    };

    pub const Optional = struct {
        // Engine-defined types: object pointers are raw borrowed pointers;
        // builtins/Variant travel by value as borrowed aliases. The return slot
        // takes its own reference to a returned `RefCounted` object.
        pub const _getImage = *const fn (self: *const Texture2D) callconv(.c) ?*Image;
    };

    pub const Meta = struct {
        pub const _getWidth = .{ .hash = 123, .static = false, .godot_name = "_get_width" };
        pub const _getImage = .{ .hash = 456, .static = false, .godot_name = "_get_image" };
    };
};
```

- `Required` and `Optional` are the registration categories.
- `Meta` supplies the engine hash, staticness, and exact `godot_name` from the API JSON.
- No binding-level function types are emitted.
- The generated signature uses public Zig types matching the engine ABI:
  object pointers are raw borrowed pointers (`?*Class`), while builtins and
  `Variant` travel by value. `RefCounted` returns are `?*Class`.
- The generated callable wrappers that invoke a virtual from Zig are ordinary
  generated methods, so a `RefCounted` engine result comes back as
  `ownership.Ref(Class)`. Only the user override signatures stay raw pointers.
- The ABI slot width is inferred from the Zig type, not stored per virtual.

## User declaration

```zig
pub const Extends = godot.classes.core.Texture2D;

pub fn _getWidth(self: *const @This()) i32 {
    return 64;
}
```

Rules:

- Required virtuals must be declared; missing is a compile error.
- Optional virtuals are registered only when declared; otherwise the engine uses
  the base implementation.
- Non-static virtuals must take `*T` or `*const T` as the first parameter.
- Remaining parameter and return types must match the generated virtual type.
  Object pointers stay raw borrowed; by-value builtins/`Variant` arguments are
  borrowed aliases. A `RefCounted` return is `?*Class`, never
  `godot.ownership.Ref(Class)`.
- Functions must not be generic.
- Static virtuals have no self parameter.
- An alternate Zig declaration name may be provided with
  `godot.annotations.Override("_engine_name", fn)`. That marker declares
  `marker.Kind.override`; discovery checks the kind and still validates the
  function against the generated virtual signature. See
  [annotations.md](annotations.md#marker-identity).

## Lookup

`Virtuals.collect(T, Base)` returns the declared entries with a specialized
callback:

```zig
pub const Entry = struct {
    name: [:0]const u8,        // Zig declaration name
    godot_name: [:0]const u8,  // engine-facing name
    hash: u32,
    callback: interface.ClassCallVirtual,
};
```

The result is a comptime static slice: the entry table and its specialized
callbacks are produced during analysis, not allocated per class or instance.

`get_virtual_func` compares `p_name` and `p_hash` against these entries. `entry.godot_name` comes directly from `Virtual.Meta`; registration does not re-run a naming conversion:

```zig
if (p_hash == 0 or p_hash == entry.hash) {
    if (name.opEqlStringName(&StringName.fromComptimeLatin1(entry.godot_name))) {
        return entry.callback;
    }
}
```

`get_virtual_func` selects by name and hash.

## Inherited virtuals

Generated `Virtual.Required`, `Virtual.Optional`, and `Virtual.Meta` include
inherited virtuals. The callback self type is the derived class, even when the
declaration originated in a base class. Required inherited virtuals must still
be declared on the concrete class; optional inherited virtuals are registered
only when declared.

## Callback ABI

Godot calls:

```zig
fn callback(
    p_instance: interface.ClassInstancePtr,
    p_args: [*c]const interface.ConstTypePtr,
    r_ret: interface.TypePtr,
) callconv(.c) void
```

- `p_instance` is the user extension instance (`T`), not the engine base pointer.
- `p_args` excludes self.
- For static virtuals, `p_instance` is unused and `p_args[0]` is the first
  argument.

All virtual argument/return marshalling goes through the internal conversion
layer's ptrcall path: the callback decodes each argument and writes the return
into the engine slot. For scalar and builtin values the canonical slot layout
comes from [abi.zig](../src/godot/abi.zig), the dependency-free helper also
available as `godot.abi`, which decides the slot from the Zig type:

- `float` / `real_t` -> `f64` slot + `@floatCast`
- normal integers -> `i64` (or `u64` when the integer is u64)
- enums -> their canonical integer slot (`i64`; `u64` for a 64-bit unsigned backing)
- packed bitfield structs -> canonical `i64` slot
- `bool` -> `u8`
- everything else -> its declared layout

This slot mapping is not virtual-specific. Registration validates ptrcall support
for every parameter and non-void return, and `virtuals.zig` supplies only the
callback shape.

`Variant` parameters and returns also travel here as ptrcall slot values (a
pointer to Variant storage), never through the Variant call path; real virtuals
such as `Control._getDragData() -> Variant` and
`AnimationMixer._post_process_key_value(..., Variant) -> Variant` do this. The
Variant call path exists only for registered extension methods.

## RefCounted arguments and returns

The virtual ABI stores `RefCounted` values differently: arguments arrive as
engine reference pointers and returns are written into engine-owned reference
storage. The internal ptrcall layer handles that:

- an argument slot is borrowed engine-owned reference storage, so the decoded
  argument is a borrowed pointer;
- a return slot is engine-owned reference storage: writing gives the slot a
  reference (for an already-referenced object it adds one; for a fresh object
  `init_ref` consumes the creation reference instead). See
  [ownership.md](ownership.md#engine-boundary).

For the generated signature and for user code this means:

- Arguments stay raw and borrowed (`?*Class` or `*Class`). The pointer is valid
  for the call; take `godot.ownership.Ref(Class).init(pointer)` before keeping it.
- Returns stay raw and borrowed too: declare `?*Class` (or `*Class`). The
  callback's conversion write hands the pointer to the engine's return slot,
  which takes the object itself, so there is no wrapper to hand over or release
  afterwards.
- Return a borrowed pointer you keep alive elsewhere (for example `.get()` of a
  stored `Ref`): your reference is untouched and the slot takes its own.
- Return a newly constructed object by moving its typed handle out through a
  local wrapper - `take()` needs a mutable wrapper, so an rvalue
  `construct().take()` does not compile:

  ```zig
  var value = godot.classes.core.AudioEffectInstance.construct();
  return value.take();
  ```

  The engine slot receives the raw pointer, and a fresh object's creation
  reference moves into the slot's `Ref` storage. To keep a newly constructed
  object too, store the `Ref` (or, for a non-`RefCounted` class, the `Owned`) in
  your state and return `.get()`; do not hand the same creation reference out
  twice.
- The ownership model is stated once in
  [ownership.md](ownership.md#the-model).

Registered extension methods are the other side of the same boundary: the engine
calls them, so a method returns outgoing values. A raw `?*T` method result is
borrowed like a virtual return; an owned `RefCounted` result is declared as
`godot.ownership.Ref(T)` because the method adapter releases the wrapper after
encoding. Only the virtual override signature is fixed to raw pointers; see
[classdb.md](classdb.md#d4-methods-are-declared-in-one-methods-container).

## Do not use upcast/downcast here

`upcast`/`downcast` are user-facing convenience methods. Virtual slots already
have the static ABI type. Using `downcast` would add an engine class lookup for
no ABI benefit.

## Variant and non-trivial builtins

Every virtual argument is a borrow: object pointers are borrowed pointers, and
by-value builtins/`Variant` are borrowed value aliases. The engine owns the
storage and cleans it up after the callback. Never deinitialize or store an
argument value; copy it if it must outlive the call (`String.fromString`,
`Variant.clone`, etc.). A stored alias is a use-after-free/double-release bug,
not a leak: the callback acquired no reference.

Return values are transferred to the engine. Godot's virtual thunk
default-constructs the return temp before calling the extension, so the callback
writes directly into `r_ret` and does not deinitialize it afterwards. Return an
owned `Variant`/`String`/`Array` and let the write move it into the slot;
returning a borrowed argument directly can double-own its internal references,
so clone it first. `RefCounted` returns are raw borrowed pointers retained by the
engine slot, as described above; see [ownership.md](ownership.md).
