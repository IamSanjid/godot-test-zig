# Ownership and lifetime

Engine objects have two typed ownership handles and borrowed views. This page
states the rule once; pages that use it link here instead of restating it.

## The model

| Type | Semantics | Use |
|---|---|---|
| `godot.ownership.Ref(T)` | Shared, reference-counted: owns exactly one engine reference to `T`, a `RefCounted` class or a subclass. `deinit` releases it; the last release destroys the object. | Engine-method results, `Property` storage, any owned `RefCounted` value. |
| `godot.ownership.Owned(T)` | Exclusive manual ownership: owns one non-`RefCounted` object and `deinit` destroys it through `Object.destroy`. There is no reference count. | Only unparented objects that nothing else owns. Never for tree-owned nodes or any object already handed to the engine. |
| `?*T` / `*T` | Borrowed for the current call; this code owns nothing. | Arguments, virtual returns, container element views, `get()` reads. |
| `godot.annotations.Base(T)` | Borrowed parent view installed on the extension instance by registration. | Reaching the engine base from an extension class. Never deinitialize it. |

- Both handles are pointer-sized and pointer-aligned. `Ref(T)` requires `T` to be
  `RefCounted` or inherit it; `Owned(T)` requires a class that is not
  `RefCounted` (compile error otherwise).
- `Ref(T)` is the only ownership handle with a declared conversion: engine type
  `?*T`, both paths, `from_engine` retains. That is what makes it valid as a
  `Property` value or a `Signal` argument. `Owned(T)` deliberately has no
  `Conversion` marker and cannot be property or signal storage; pass `.get()` as
  a raw borrowed pointer or `.take()` to hand the object on.
- Storage says its policy in the type: a `Property` field that keeps a
  `RefCounted` value declares `Ref(T)`; a raw `RefCounted` pointer is a compile
  error. Non-`RefCounted` object pointers stay raw and borrowed because the
  engine owns those objects. See
  [properties.md](properties.md#ownership-modes).
- Generated engine-method results hand you an owning `Ref(T)` for a `RefCounted`
  result; their arguments stay raw and borrowed. An engine method that returns a
  non-`RefCounted` object returns a borrowed raw pointer.
- Virtual callbacks take and return raw borrowed pointers, including
  `RefCounted` returns: the engine's return slot takes the object itself
  (engine-owned reference storage), so no wrapper is handed over or released.
  See [virtuals.md](virtuals.md#refcounted-arguments-and-returns).
- Copies of a `Ref` alias the same reference. Keep one wrapper per reference:
  use `clone()` (or `init(borrowed)`) to take another reference instead of
  copying a wrapper you will also deinit. `Owned` has no copy step: move it with
  `take()` or keep it in a single wrapper.
- Both handles expose `empty` (the null handle) and `isNull()`. Construct an
  empty wrapper with `Ref(T).empty`/`Owned(T).empty`; there is no implicit
  default for a `Property` field, so declare `= .init(Ref(T).empty)` (or another
  owned value) as the field default. `deinit` on an empty wrapper is a no-op.

## Construction

`Class.construct()` and `Class.constructLegacy()` on a generated class return the
class's typed handle: `Ref(Class)` when the class inherits `RefCounted`,
`Owned(Class)` otherwise. The raw bindings still return `?*Class`; the generated
wrapper moves that pointer into the handle with a struct literal, taking over the
creation pointer (and its creation reference for `RefCounted`). The same struct
literal is used by generated `Ref`-returning engine-method adapters, which take
over the reference the binding returns. This literal is internal to codegen; user
code uses the typed result.

```zig
var resource = godot.classes.core.Resource.construct(); // Ref(Resource)
defer resource.deinit();

var node = godot.classes.core.Node.construct(); // Owned(Node)
defer node.deinit();
```

- `construct()` uses `classdb_construct_object3`: no implicit
  `NOTIFICATION_POSTINITIALIZE`, and a `RefCounted` result already has refcount 1.
  Registration uses this form and sends the notification itself when the engine
  asks for it.
- `constructLegacy()` uses the deprecated interface, which sends
  `NOTIFICATION_POSTINITIALIZE` internally; the binding also calls `init_ref`
  for a `RefCounted` class. Its typed handle still owns exactly one creation
  reference.
- Dispose with `deinit()`: `Ref.deinit` releases the reference and destroys the
  object when it was the last one; `Owned.deinit` destroys the object
  immediately.
- Move a newly constructed handle into the field or slot that should own it; do
  not deinit the moved-from local (see
  [Moving and borrowing](#moving-and-borrowing)).

### Create-instance factory

For a registered extension class the runtime builds the engine base with
`Base.construct()` and receives its typed handle. The engine's
`create_instance3` contract expects a `RefCounted` base with refcount 1, which is
what `classdb_construct_object3` returns, so the factory hands the raw base to
the engine with `.take()` on success. On every failure path it releases the
handle with `.deinit()` instead: that drops the creation reference for a
`RefCounted` base and destroys a non-`RefCounted` one. When `InitCallback`
returns an error, creation and recreation detach and destroy the Zig instance;
creation also releases the base. The framework does not run
`annotations.deinitPropertyFields` there, and `DeinitCallback` does not run: a
field without a default or `.init` initializer may still be undefined, so a
blanket cleanup is unsafe. It runs a partial best-effort cleanup instead, before
the instance is detached: fields with a custom `.init` initializer and
`.deinit = .best_effort` release the value the initializer stored. Custom
`.deinit` hooks are skipped (the owner may be partially initialized), and values
`InitCallback` created or assigned are not tracked; init code owns those.
`.init` values on fields whose cleanup is a custom hook still leak. Known leak
limitation on the init-failure path; revisit only with initialized-field
tracking. See [registration.md](registration.md#instance-lifecycle).

After `create_instance` returns, the engine owns the base and its lifetime is the
engine's. `free_instance` is the base object's destructor hook - the engine calls
it from `Object::_predelete` during normal destruction and from the reload path -
so it only deinits the Zig instance and cleans its properties; it must never free
or unreference the base. The `Base` marker is a borrowed view; never deinit it.
See [registration.md](registration.md#instance-lifecycle).

## Moving and borrowing

`take()` and `get()` are the two directions:

- `get()` returns the raw pointer without changing ownership. Use it for a
  borrowed value: a call argument, a read of a stored handle, or a virtual return
  of an object you keep alive elsewhere.
- `take()` moves the owned pointer out and empties the wrapper. Use it when
  ownership leaves the Zig side: the create-instance factory handing the base to
  the engine, a constructed node handed to the tree with `addChild`, or a
  constructed virtual return. The receiver owns the pointer afterwards.
- `clone()` takes another reference on the same `RefCounted` object;
  `init(borrowed)` turns a borrowed pointer into an owner. `Owned` has neither:
  its only sources are `Class.construct()` and a `take()` from another `Owned`.
- `get()`/`take()` on an empty wrapper are safe and return `null`; `isNull()`
  reports the state.

Passing a wrapper by value is an alias, not a transfer. Do not deinit a wrapper
after moving it into a field, returning its `.get()`, or calling `.take()` on it.
Do not build a wrapper with a struct literal (`.{ .ptr = ... }`): it looks like a
borrow but claims ownership; only codegen's `construct` adapter uses it, to take
over a creation reference.

```zig
// The field takes over the created resource's reference.
self.resource.value = godot.classes.core.Resource.construct();

// Borrow the stored object for an engine call; the wrapper keeps its reference.
some_api(node.get());
```

### Virtual returns

A virtual return is a raw borrowed pointer for every object type. Return a stored
handle with `.get()`; the engine slot takes the returned object itself, so your
reference is untouched. Return a newly constructed object by moving its handle
out through a local wrapper - `take()` needs a mutable wrapper, so an rvalue
`construct().take()` does not compile:

```zig
pub fn _instantiate(self: *@This()) ?*AudioEffectInstance {
    _ = self;
    var value = godot.classes.core.AudioEffectInstance.construct();
    return value.take();
}
```

The engine return slot is `RefCounted` reference storage: writing the returned
pointer gives the slot its reference (a fresh object's creation reference moves
into that storage through `init_ref`), and nothing is released after the
callback. A `Base` field is never returned or deinitialized. More in
[virtuals.md](virtuals.md#refcounted-arguments-and-returns).

## `Owned` caveats

`Owned(T)` is for objects that nothing else owns. It is not a general
non-`RefCounted` wrapper:

- Never put a scene-tree node, or any object the engine stores or owns, in an
  `Owned(T)` handle. The tree/engine would destroy it while `Owned.deinit` also
  destroys it.
- Hand the object to its new owner with `take()`: `addChild` takes tree ownership,
  create-instance returns the base to the engine, and a constructed virtual
  return goes to the engine slot. After `take()` the wrapper is empty and must
  not be deinitialized.
- `deinit()` destroys immediately; there is no shared ownership and no way to
  take another reference.
- `Owned` is not a conversion type and has no engine representation of its own.
  Store a `Ref` for `RefCounted` values; for borrowed object pointers keep the
  raw `?*T`.
- The class picks the handle: `Node.construct()` yields `Owned(Node)` while
  `Resource.construct()` yields `Ref(Resource)`. There is no conversion between
  the two.

## Engine boundary

Consumer code only sees the handles and the raw/borrowed split above; the ABI
details stay internal:

- An **owning** Variant payload owns its object references. A pointer taken out
  of an owning Variant is borrowed while that Variant is alive; copy the Variant
  or take a `Ref` to keep the object. A borrowed object Variant (from
  `Variant.borrow` or a borrowed function argument) owns nothing and must never be
  deinitialized. See [variants.md](variants.md).
- RefCounted ptrcall slots are engine-owned reference storage. An argument slot
  is borrowed for the call, and a return slot takes its own reference when
  written. Virtual callbacks and converters use that rule and never write raw
  object pointers into a reference slot; the rules are stated in
  [conversion.md](conversion.md#ptrcall-path) and
  [virtuals.md](virtuals.md#refcounted-arguments-and-returns).
- A generated engine-method `Ref(T)` result, a successful `construct()`, and a
  decoded `Ref` converter all arrive owning one reference. Anything a converter
  retains in `from_engine` follows the same rule; see [conversion.md](conversion.md).

## Helpers

`godot.ownership` also exposes the low-level primitives `Ref` is built on:

| Helper | Use |
|---|---|
| `retainRefCounted(T, value)` / `releaseRefCounted(T, value)` | Retain or release a raw `RefCounted` pointer value. Null optionals are no-ops and non-`RefCounted` types are compile errors; `releaseRefCounted` destroys the object when it was the last reference. |
| `retainObjectReference(object: *RefCounted)` | Take an owning reference when a raw `RefCounted` pointer is known (the `RefCounted` base class, not a generic object). Non-`RefCounted` arguments are a compile-time error. Returns false when the engine refuses an object whose reference count is zero. |

Prefer `Ref`/`Owned` in user code. These helpers are for runtime internals
(Variant conversion, typed-container adapters) and for code that deliberately
stays on a raw pointer. There is no constructed-base helper: the typed handle
from `Base.construct()` owns that decision.

## Related

- [conversion.md](conversion.md) - the declared-type conversion model, its
  ownership direction, and the Variant/ptrcall consequences.
- [properties.md](properties.md#ownership-modes) - `Property` `.set`/`.deinit`
  modes and the `Ref` storage requirement.
- [variants.md](variants.md) - Variant payload ownership.
- [virtuals.md](virtuals.md#refcounted-arguments-and-returns) - callback argument
  and return rules.
- [collections.md](collections.md#ownership) - owning container wrappers.
- [registration.md](registration.md#instance-lifecycle) - create-instance and
  free-instance lifecycle.
