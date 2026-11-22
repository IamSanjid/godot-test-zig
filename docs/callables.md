# Callables

A custom callable is the only way to hand the engine a Zig function: the engine
wraps it in a refcounted `CallableCustomExtension` and calls it from
`Object.connect`, `Callable.call`, deferred calls, and signal emission.

Status: design. The declared-type conversion it depends on is implemented as
`Variant.initDeclared`/`asDeclared`; the closure constructor is not.

## Engine contract

Current entry points are `callable_custom_create2` and `GDExtensionCallableCustomInfo2`.

- Only `call_func` and `token` are strictly required. `object_id` should be set
  for anything that is not a static function.
- `call_func(userdata, p_args, count, r_return, r_error)` receives **borrowed**
  Variants that are valid only for the call, and an **engine-owned** return slot
  to assign into. Never retain the argument Variants and never destroy the
  return slot.
- `r_error` arrives **uninitialized** and must be filled: `CALL_ERROR_NONE` on
  success, `CALL_ERROR_INVALID_ARGUMENT` with `argument`/`expected` when a
  conversion fails. Leaving it untouched makes the engine read garbage.
- `free_func` is called **exactly once per `callable_custom_create2` call**,
  from the wrapper's destructor, when the last `Callable`/`Variant` copy dies.
  It is never called per copy.
- `callable_userdata` is opaque to the engine: stored, passed back, and
  pointer-compared. The extension owns its lifetime.
- Null callbacks: `is_valid_func` null means "always valid"; `free_func` null
  leaks; `hash_func`/`equal_func`/`less_than_func` null means identity is the
  (`call_func`, `userdata`) pair.
- Equality: two custom callables compare equal only when both carry the same
  `equal_func` pointer, and then it is called. Hashes are cached once, so
  `a == b` must imply `hash(a) == hash(b)`.
- `token` is used only by `callable_custom_get_userdata(callable, token)`, the
  sanctioned "is this my callable?" probe. Use the library pointer.
- `object_id = 0` is legal for an object-less closure: `get_object()` is null,
  no reverse connection entry exists (so the connection is not auto-removed
  when an object dies), and deferred calls still deliver.
- `call_func` runs on the emitting or calling thread. Signal emission is
  serialized per object, but different objects may emit concurrently, and
  emitted Variants are the only synchronization the engine provides.
- Hot reload: there is no engine guard. A callable that outlives the library
  unload is undefined behavior; disconnect before unload. The sample
  `.gdextension` in the README sets `reloadable = true`, so a callable that
  holds extension code must be disconnected before a reload.

## Decisions

### D1. Hand-written runtime module; the type stays generated

`Callable` remains a codegen builtin (`builtins/generated/callable.zig`): the
generator owns the type and its engine methods, and `deinit` already exists, so
ownership works. The closure constructor is hand-written
(`src/godot/callable.zig`) because it is policy - allocation, callbacks,
identity, conversion - and hand-written policy must be compiled and tested
directly. A codegen overlay would only compile after `zig build gen`, which is
the wrong feedback loop for this code.

### D2. Boxed context, typed handler

```zig
const Ping = struct { count: u32 = 0 };

fn onPing(self: *Ping, health: i32, source: *godot.classes.core.Node) void {
    self.count += 1;
}

const callback = try godot.callable.fromClosure(Ping{}, onPing);
defer callback.deinit();
_ = emitter.connect(.Pinged, callback, .{});
```

- The context is copied into an `engine_allocator` box and freed by
  `free_func`, so the closure can outlive the creating scope. That is required:
  `connect` keeps the callable.
- The handler's first parameter is `*Ctx` or `*const Ctx`; the rest are the
  argument types; the return type is the callback return (void or any
  Variant-convertible type). Handlers are normal runtime functions, not generic.
- `get_argument_count_func` reports the declared arity. This is introspection
  only: `Object.connect` does no arity or type validation, and emit-time
  mismatch is an engine `ERR_PRINT`, not a connect-time error.
- `object_id` is 0, `to_string_func` may name the closure for debugging, and
  `hash`/`equal`/`less` stay null. Identity is therefore `(shim, box)`, and two
  `fromClosure` calls are never equal: **keep the returned `Callable` to
  disconnect**.
- Argument and return conversion goes through `Variant.initDeclared` and
  `Variant.asDeclared`, the same operations properties and signals use. A
  Zig-emitted signal and a Zig closure receiving it therefore agree on literals,
  extension-instance reduction, nulls, and class checks.

### D3. Typed `connect` comes after the closure

`Object.connect` takes a `Callable` and validates nothing, so the only place
handler signatures can be checked is where the declared argument types are
known: a class's `Signal` declarations.

```zig
// planned
const handle = try emitter.connect(.PathChanged, .{ &state, onPathChanged });
defer handle.disconnect();
```

That helper looks up the signal entry (names and types), checks the handler
signature at compile time, builds the closure, connects, and returns a handle
that owns the `Callable`. The handle is not sugar: a custom callable's identity
is its pointer, so a later `disconnect` cannot rebuild an equal one.

Engine-class signals (`Node.Ready`) have no argument metadata in codegen yet, so
they stay untyped (`Object.connect`). Emitting signal argument metadata from
`extension_api.json` is a legitimate later codegen addition - it is data, not
registration - but it is not needed for user signals.

### D4. Deferred and one-shot work unchanged

`CONNECT_DEFERRED` deep-copies the arguments into the message queue and
re-checks `is_valid` at flush time, so a custom callable needs no extra
handling there. One-shot connections (`CONNECT_ONE_SHOT`) clean the callable up
normally through the refcount.

## Ownership summary

- `fromClosure` returns an owned `Callable`; `.deinit()` releases it, and
  `free_func` runs when the last copy dies.
- `connect` copies the callable; after connecting, the local copy may be
  released and the connection keeps it alive.
- To disconnect, pass the same `Callable` value (or use the future handle)
  before releasing it.
- Never pass the same userdata to two `callable_custom_create2` calls: two
  wrappers mean two `free_func` calls and a double free.
- The engine may keep the callable in the queue or in a connection, so neither
  the box nor anything it points to may be stack storage.

## Non-goals

- no `less_than_func` (sorting only; godot-cpp calls it niche)
- no value equality across separately created closures (pointer identity, same
  trade-off as godot-rust)
- no automatic disconnect on hot reload
- no Zig callable for engine methods beyond the generated
  `Callable.initObjectMethod` / `Callable.create`

## Verification

Compile-only until a real engine run.
