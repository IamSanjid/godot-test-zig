# Registration

Registration is an optional convenience layer. The low-level pieces are usable
without `Registry`.

## Class data vs class options

```zig
pub const ClassOptions = struct { // comptime
    auto_onready: bool = false,
    // is_virtual, is_abstract later, once creation modes exist
};

pub const AddClassData = struct { // runtime, heap-stored per addClasses call
    create_allocator: Allocator,
    gpa: ?Allocator = null,
    register_at_level: interface.InitializationLevel = .scene,
};
```

- `ClassOptions` is comptime because it changes generated/runtime callback shape.
- `AddClassData` is the runtime value stored through `class_userdata`.
- `create_allocator` creates and frees the user instance.
- `gpa` is passed to `InitCallback` and `DeinitCallback`. If null,
  `create_allocator` is used. `OnReady` initialization receives owner/base, not
  an allocator.
- Different groups can have different allocators and registration levels.

## Grouped registration

The multi-class form is intentional:

```zig
registry.addClasses(
    .{ A, B, C },
    .{ .auto_onready = true },
    .{
        .create_allocator = pool,
        .gpa = gpa,
        .register_at_level = .scene,
    },
);
```

One class is simply a one-element group:

```zig
registry.addClasses(.{A}, .{}, .{ .create_allocator = allocator });
```

`addClasses` allocates one `AddClassData` for the call. All classes in that call
share it. Use another call for another group.

The class name is `T.GodotClassName` when present, otherwise the short Zig type
name. Duplicate names are rejected. `addClasses` also accepts a namespace struct
and registers its first-level public extension-class declarations.

`addClasses` returns errors such as `DuplicateClassName`. Report registration
failure from the entry symbol and fail extension startup.

## Extension-class parents

A registered extension class must directly extend an engine class. The Godot 4
extension API does not support extension-to-extension class inheritance, so
`Registry` rejects it with a compile error. `reflect` can still analyse an
extension-to-extension `Extends` chain, but it cannot be used as a registered
class parent yet.

## Registry is optional

A user who wants a different registration model can use the builders directly:

- create-instance callback
- free-instance callback
- notification callback
- virtual lookup callback

Then they can call `classdb_register_extension_class6` themselves. No pooling,
arena, or instance-creation policy is forced by `Registry`.

## Where registration runs

- `godot.init` installs the initialize/deinitialize callbacks and creates the
  process-wide `Registry`.
- `godot.initialize` registers each class at its `AddClassData.register_at_level`.
- `godot.deinitialize` unregisters only classes belonging to that level and keeps
  the rest. At the configured minimum level it unregisters any remaining classes,
  frees the registry arena, and marks the registry uninitialized.
- Call `godot.registry().addClasses(...)` from the entry symbol after
  `godot.init` and before returning. Registration errors should fail the entry
  symbol.

## Instance lifecycle

Creation order for a registered class:

1. Construct the engine base with `Base.construct()` (no implicit
   post-initialize; RefCounted already has refcount 1).
2. Allocate the user instance with `create_allocator`.
3. Initialize field defaults (`reflect.initFieldsDefault`).
4. Initialize annotation fields (`annotations.initAnnotFieldsDefault`).
5. Initialize the `Base` marker field.
6. Call the optional `InitCallback`.
7. Set the engine instance binding.
8. Send post-initialize notification only when `p_notify_postinitialize` is true.

Freeing:

1. Call the optional `DeinitCallback`.
2. Destroy the user instance with `create_allocator`.

`reflect.initFieldsDefault` only initializes fields that declare defaults.
Fields without defaults are the user's responsibility: provide a default,
initialize them in `InitCallback`, or accept that they are undefined until set.
The runtime does not force a zero-initialization policy.

For a class extending `RefCounted`, `construct` returns an object
with refcount 1, which the engine create-instance contract expects. Do not call
`initRef` or `unreference` on the extension object manually; `free_instance`
runs when the engine releases it.

`initFieldsDefault` is a generic helper and remains public. It is not
annotation-specific.

Generated binding classes expose two constructors:

- `construct()` uses `classdb_construct_object3`: no implicit
  `NOTIFICATION_POSTINITIALIZE`, and no `init_ref` for `RefCounted`.
- `constructLegacy()` uses `classdb_construct_object`: that interface sends
  `NOTIFICATION_POSTINITIALIZE` internally, and the generated helper additionally
  calls `init_ref` for `RefCounted`. It is omitted when the generator runs with
  `--strip-deprecation` because the underlying interface function is compiled
  out in that mode.

Registration uses `construct()` and sends post-initialize itself only when the
engine asks for it.

## OnReady

`initAnnotFieldsDefault` initializes marker fields to their default wrappers.
Actual `OnReady` values are initialized:

- automatically when `auto_onready = true`, the class extends `Node`, declares at
  least one `OnReady` field, and the class has a `Base` marker, on
  `post_enter_tree`, or
- manually by calling `godot.annotations.initOnReadyFields(...)`.

Auto-OnReady is opt-in. A non-`Node` class that enables it with `OnReady` fields
is rejected with a compile error, because only `Node` sends the
`post_enter_tree` notification it waits for. The notification route remains
available.

## Namespace detection

`isLikelyNamespace` is only a shape check: a zero-field, non-tuple struct. A
zero-field struct may still be a valid extension class, so registration checks
`reflect.isExtensionClass(Class)` first and only treats the struct as a namespace
when that check fails and `isLikelyNamespace` passes. Engine classes and other
types are rejected with a compile error.

## Virtual and abstract classes

`is_virtual` and `is_abstract` will be added as comptime `ClassOptions` only when
their callback behavior is implemented. They affect whether creation/free
callbacks are installed and how the class is exposed. They are not dead runtime
flags.
