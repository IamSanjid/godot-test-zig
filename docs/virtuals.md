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
- The generated signature uses public Zig types; ABI slot conversion happens in
  `src/godot/abi.zig` via the virtual callback adapter.
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
- Functions must not be generic.
- Static virtuals have no self parameter.

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

All virtual argument/return marshalling goes through [abi.zig](../src/godot/abi.zig),
the same shared helper available as `godot.abi`. It decides the slot from the
Zig type:

- `float` / `real_t` -> `f64` slot + `@floatCast`
- normal integers -> `i64` (or `u64` when the integer is u64)
- enums -> their canonical integer slot (`i64`; `u64` for a 64-bit unsigned backing)
- packed bitfield structs -> canonical `i64` slot
- `bool` -> `u8`
- everything else -> its declared layout

This is not virtual-specific. Any future ptrcall-facing code can call
`godot.abi.readArgument` / `godot.abi.writeReturn` directly. `virtuals.zig` only
adds the RefCounted `Ref<T>` rules and the callback shape on top.

## RefCounted is the exception

Godot virtual ABI represents `RefCounted` values differently:

- `RefCounted` arguments arrive as `Ref<T>*`, not `Object**`.
- `RefCounted` returns are `Ref<T>` storage, not `Object*`.

Use the interface procedures:

### Argument

```zig
if (comptime isRefCountedPointer(P)) {
    const ref: interface.ConstRefPtr = @ptrCast(@alignCast(p_args[i]));
    const object = runtime.dispatch(.ref_get_object, .{ref});
    args[i] = if (object) |p| @ptrCast(p) else null;
} else {
    args[i] = @as(*const P, @ptrCast(@alignCast(p_args[i]))).*;
}
```

The returned object pointer is borrowed for the call. Taking ownership requires
an explicit reference.

### Return

```zig
if (comptime isRefCountedPointer(R)) {
    const object: interface.ObjectPtr = if (result) |p| @ptrCast(p) else null;
    runtime.dispatch(.ref_set_object, .{
        @as(interface.RefPtr, @ptrCast(@alignCast(r_ret))),
        object,
    });
} else {
    @as(*R, @ptrCast(@alignCast(r_ret))).* = result;
}
```

Do not assign a raw pointer into `Ref<T>` storage.

`isRefCountedPointer` lives in `reflect`: it resolves the single-item class
pointer through `reflect.objectTarget` and checks
`reflect.inheritsFrom(Class, classes.core.RefCounted)`. The virtual callback keeps
only the ABI decision to call `ref_get_object` / `ref_set_object`.

## Do not use upcast/downcast here

`upcast`/`downcast` are user-facing convenience methods. Virtual slots already
have the static ABI type. Using `downcast` would add an engine class lookup for
no ABI benefit.

## Variant and non-trivial builtins

Virtual arguments are borrowed views. The engine owns the argument storage and
will clean it up after the callback. Never deinitialize argument values.

Return values are transferred to the engine. Godot's virtual thunk creates the
return temp before calling the extension, so the callback writes directly into
`r_ret`; there is no previous non-empty value to release. Return an owned
Variant/String/Array and do not deinitialize it after writing to `r_ret`.
Returning a borrowed argument directly may double-own its internal references;
clone it first when ownership is required. `RefCounted` returns are stored by
`ref_set_object`, which adds a new owning reference to engine-owned `Ref<T>`
storage; release any reference you own separately.

See [ownership.md](ownership.md).
