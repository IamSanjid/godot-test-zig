# Registration

Registration is an optional convenience layer. The low-level pieces are usable
without `Registry`.

## Public surface

The facade exposes the registration layer as a module plus a convenience type:

```zig
godot.registration.Registry
godot.registration.ClassOptions
godot.registration.ClassRegistration
godot.registration.PostRegistrationCallback
godot.registration.instance
godot.registration.notification
godot.registration.property
godot.registration.virtuals
godot.registration.classdb

godot.registration.CreateInstance
godot.registration.RecreateInstance
godot.registration.FreeInstance

godot.Registry // == godot.registration.Registry
```

The helpers in `registration/*.zig` are usable without `Registry`, but they
still belong to this template's hand-written runtime and codegen stack; the
registration layer is not a standalone package. `Registry` adds grouping and
lifecycle convenience.

## Class data vs class options

```zig
pub const ClassOptions = struct { // comptime
    auto_onready: bool = false,
    auto_property_cleanup: bool = false,
    is_exposed: bool = true,
    is_runtime: bool = true,
    icon_path: ?[:0]const u8 = null,
    is_virtual: bool = false,
    depth: u8 = 2,
};

pub const ClassRegistration = struct { // runtime, heap-stored per addClasses call
    instance_allocator: Allocator,
    gpa: ?Allocator = null,
    register_at_level: interface.InitializationLevel = .scene,
};
```

- `ClassOptions` is comptime: it selects callback shape (`auto_onready`,
  `auto_property_cleanup`), supplies the per-group `ClassCreationInfo6` flags
  (`is_virtual`, `is_exposed`, `is_runtime`, `icon_path`), and controls namespace
  traversal (`depth`).
- `ClassRegistration` is the runtime value stored through `class_userdata`.
- `instance_allocator` creates and frees the user instance.
- `gpa` is passed to `InitCallback` and `DeinitCallback`. If null,
  `instance_allocator` is used. `OnReady` initialization receives owner/base, not
  an allocator.
- `auto_property_cleanup` is compile-time policy and off by default. `Registry`
  passes it to `FreeInstance(T, Base, auto_property_cleanup)`. When true, the
  free-instance callback runs `annotations.deinitPropertyFields` on the class's
  `Property` fields after `DeinitCallback`. Property fields are user-managed
  without it. Standalone users pass the boolean directly to `FreeInstance`, or
  call the helper from their own free callback.
- `is_exposed = false` hides the class from ClassDB/editor class listings.
- `is_runtime = true` (default) registers a runtime class: the editor builds a
  placeholder from the native base instead of the extension instance, so
  extension code does not run there. Set it to false for tool classes that must
  run in the editor. This only matters in editor builds; runtime builds always
  use the real class.
- `icon_path` is an editor-only `res://` icon path; `Registry` keeps its
  process-lifetime `String` and never frees it.
- `is_virtual = true` hides the class from editor creation dialogs, the resource
  picker, and docs while keeping it instantiable: it installs every callback. It
  requires `is_exposed = true`, because `ClassDB::is_virtual()` reports
  `can_instantiate(class) && is_virtual`; the combination is a compile error.
  See [classdb.md](classdb.md).
- `depth` controls namespace traversal: `1` registers direct extension classes
  only; `2` (default) also descends one nested namespace level.
- Different groups can have different allocators and registration levels.

## Grouped registration

The multi-class form is intentional:

```zig
try registry.addClasses(
    .{ A, B, C },
    .{ .auto_onready = true },
    .{
        .instance_allocator = pool,
        .gpa = gpa,
        .register_at_level = .scene,
    },
);
```

One class is simply a one-element group:

```zig
try registry.addClasses(.{A}, .{}, .{ .instance_allocator = allocator });
```

`addClasses` allocates one `ClassRegistration` for the call. All classes in that call
share it. Use another call for another group.

The class name is `T.GodotClassName` when present, otherwise the short Zig type
name; a file-root class therefore uses its file stem. Two files with the same
stem collide at runtime, so give one of them an explicit `GodotClassName`.
Duplicate names are rejected. `addClasses` also accepts a namespace struct
and registers the extension classes it contains, expanding nested public
namespaces up to `ClassOptions.depth`.

`addClasses` returns errors such as `DuplicateClassName`. Report registration
failure from the entry symbol and fail extension startup.

## Scanned class groups

`build/class_files.zig` can generate a namespace module from files containing
`pub const Extends =`:

```zig
try registry.addClasses(
    .{ @import("example.gen.zig") },
    .{ .auto_onready = true, .is_runtime = false },
    .{ .instance_allocator = allocator },
);
```

Use separate generated modules when groups need different `ClassOptions`,
allocators, or registration levels:

```zig
try registry.addClasses(
    .{ @import("game.gen.zig"), @import("editor.gen.zig") },
    .{ .is_runtime = false },
    .{ .instance_allocator = allocator },
);
```

The generated module is a namespace of file-root classes and namespaces;
`addClasses` expands public types up to `ClassOptions.depth` (default 2). A file
that is itself an extension class registers directly; a file namespace with a
nested class, like `test_node2.zig`, is reached through that depth. The scanner
is example build wiring, not a registration-layer dependency; see
[docs/build.md](build.md).

## Extension-class parents

A registered extension class must directly extend an engine class. The Godot 4
extension API does not support extension-to-extension class inheritance, so
`Registry` rejects it with a compile error. `reflect` can still analyse an
extension-to-extension `Extends` chain, but it cannot be used as a registered
class parent yet.

## Registry is optional

A user who wants a different registration model can use the builders directly:

- create-instance callback (`CreateInstance`)
- recreate-instance callback (`RecreateInstance`)
- free-instance callback (`FreeInstance`)
- notification callback
- virtual lookup callback

Then they can call `classdb_register_extension_class6` themselves. No pooling,
arena, or instance-creation policy is forced by `Registry`. A standalone create
callback must follow the same [creation order](#instance-lifecycle), including
attaching the instance before `.init` initializers and `InitCallback`;
`RecreateInstance` runs that same sequence when the engine reloads the library.
Generated classes expose `attachInstance(T, instance)`, `asInstance(T)`, and
`detachInstance(T)` for manual binding. All three must use the same class and
`T` (the extension's direct engine parent, `EngineBaseType(T)`), because the
binding token is per class and type; `typeToken(T)` returns that token. Detach
before destroying an attached instance; the engine keeps the class's extension
pointer, so the bundled property, notification, and free callbacks then see a
null instance. Virtual and method dispatch cannot run on a detached instance. For property cleanup, pass
`true` to `FreeInstance`, or call `annotations.deinitPropertyFields` from the
free callback directly.

Signals and integer constants are not part of `ClassCreationInfo6`. A class
registered without `Registry` still needs its class-level metadata written: call
`godot.registration.classdb.postRegistrationCallback(T)` with the same library
and class name immediately after `classdb_register_extension_class6`, at the same
level. Skipping it registers a class whose signals fail to connect and whose
constants do not exist, with no compile error.

## Where registration runs

- `godot.init` installs the initialize/deinitialize callbacks and creates the
  process-wide `Registry`.
- `godot.initialize` registers each class at its `ClassRegistration.register_at_level`.
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
2. Allocate the user instance with `instance_allocator`.
3. Initialize field defaults (`reflect.initFieldsDefault`).
4. Reset default-initialized annotation fields
   (`annotations.initAnnotFieldsDefault`): the `OnReady` wrappers go back to
   `value = null`. No user code runs and the base is not used.
5. Initialize the `Base` marker field (`annotations.initBase`).
6. Attach the extension instance to the engine base
   (`base.attachInstance(T, child)`). The extension pointer and instance binding
   are installed here; a failed creation detaches them again.
7. Run eager `Property` `.init` initializers
   (`annotations.initPropertyFields`), with the instance attached.
8. Call the optional `InitCallback`.
9. Send the post-initialize notification only when `p_notify_postinitialize` is
   true.

The attach at step 6 precedes the property-initializer loop, so engine calls
made from a `.init` initializer see the extension instance. The field-order
contract is in
[properties.md](properties.md#creation-time-initializers).

If `InitCallback` returns an error, creation fails: the engine instance is
detached and its instance binding freed, then the Zig instance and the engine
base are destroyed. Releasing the base depends on its kind:
[ownership.md](ownership.md#construction) records the rule. `DeinitCallback` and
property cleanup do not run, even when `auto_property_cleanup` is enabled, and
values already assigned by `Property` `.init` initializers are not cleaned
either. Init code must release anything it created before returning the error.

The lifecycle callbacks are declaration markers. `InitCallback`,
`DeinitCallback`, and `NotificationCallback` declare `marker.Kind.init_callback`,
`deinit_callback`, and `notification_callback`; discovery checks that kind and
still validates the callback signature. Identity rule:
[annotations.md](annotations.md#marker-identity).

Freeing:

1. Call the optional `DeinitCallback`.
2. When `FreeInstance` is built with `auto_property_cleanup = true`, call
   `annotations.deinitPropertyFields(T, instance)`: each field runs its declared
   `.deinit` mode (a function, or `.best_effort` for value `deinit`/`RefCounted`
   release); a field with no `.deinit` mode is skipped. See
   [properties.md](properties.md#explicit-cleanup).
3. Destroy the user instance with `instance_allocator`.

`reflect.initFieldsDefault` only initializes fields that declare defaults.
Fields without defaults are the user's responsibility: provide a default,
initialize them with a `.init` initializer or in `InitCallback`, or accept that
they are undefined until set. The runtime does not force a zero-initialization
policy.

For a class extending `RefCounted`, `construct` returns an object
with refcount 1, which the engine create-instance contract expects. Do not call
`initRef` or `unreference` on a live extension object manually; `free_instance`
runs when the engine releases it. A failed creation is the exception: it
releases the base with `godot.ownership.releaseConstructedBase`, per
[ownership.md](ownership.md#construction).

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

At creation, `initAnnotFieldsDefault` only resets the `OnReady` wrapper to its
default (`value = null`); it does not resolve `.Node(path)` or call
`.Call(func, args)`. Actual values are resolved:

- automatically when `auto_onready = true`, the class extends `Node`, declares at
  least one `OnReady` field, and the class has a `Base` marker, on
  `post_enter_tree` while the node is not ready, or on
  `NOTIFICATION_EXTENSION_RELOADED` when the reloaded node is already inside the
  tree, or
- manually by calling `godot.annotations.initOnReadyFields(...)`.

Auto-OnReady is opt-in. A non-`Node` class that enables it with `OnReady` fields
is rejected with a compile error, because only `Node` sends the
`post_enter_tree` notification it waits for.

## Hot reload

Every class registered through `Registry` supports editor hot reload: `Registry`
installs a `recreate_instance_func` built by
`godot.registration.RecreateInstance`. The `.gdextension` file must set
`reloadable = true`; the sample in [README.md](../README.md) does. Reloading
exists only in editor builds, and the engine disables it for an extension when a
class with a creation callback has no recreate callback.

On reload the engine:

1. Stores the `PROPERTY_USAGE_STORAGE` values of every live instance, skipping
   values equal to a non-NIL class default and null objects without
   `PROPERTY_USAGE_STORE_IF_NULL`.
2. Unloads the old library: `godot.deinitialize` unregisters the classes, and
   for each live instance the engine calls our free-instance callback.
   `DeinitCallback` and opt-in property cleanup run there.
3. Loads the new library and re-runs initialization, so the classes are
   registered again.
4. Calls our recreate callback. It runs the same
   [creation sequence](#instance-lifecycle), minus `Base.construct` and the
   post-initialize notification, and installs the instance binding.
5. Restores the stored storage-usage values through the class's setter.
6. Sends `NOTIFICATION_EXTENSION_RELOADED`.

Consequences:

- `InitCallback` runs again on reload. It runs before the engine restores storage
  values, so it sees creation-time values, not saved ones.
- Only storage-usage properties are restored afterwards. Other properties and
  plain Zig fields reset to their creation-time values.
- With auto-OnReady enabled, `OnReady` fields re-resolve on
  `NOTIFICATION_EXTENSION_RELOADED` for a node that is already inside the tree;
  see [OnReady](#onready). With `auto_onready = false` they stay null unless a
  `NotificationCallback` resolves them on that notification.
- If recreation fails, the engine reports the error and the object keeps its
  base without an extension instance; do not dispatch virtuals or methods on it
  afterwards.

## Properties

When a class declares `Property` fields, registration installs the dynamic
`ClassCreationInfo6` property callbacks: `set_func`/`get_func` always, and
`get_property_list_func`/`free_property_list_func` only when at least one
property has non-zero usage. The property list is a lazy per-class static table
with process lifetime; it is never freed. Set/get values are decoded and
encoded with `godot.conversion` (`decodeVariant`/`encodeVariant`); see
[conversion.md](conversion.md).

Property options, backend dispatch, and cleanup rules are in
[properties.md](properties.md); registration only decides which callbacks are
installed.

## Class-level metadata

Signals and integer constants are not `ClassCreationInfo6` callbacks. They are
registered per class, after the class itself. `Registry` stores an optional
`post_registration_callback` for each registered class and `godot.initialize`
runs it immediately after `classdb_register_extension_class6`, for the same
class and the same initialization level:

- a class's `annotations.Signal` declarations register through
  `classdb_register_extension_class_signal`; each argument's Variant type and
  engine class name are derived through `godot.conversion` (`Variant` registers
  as untyped `.nil`; see [conversion.md](conversion.md));
- a class's `annotations.Constants` markers register integer constants, enums,
  and bitpack flags through `classdb_register_extension_class_integer_constant`;
- a class with neither stores a null callback and does no extra work.

The ordering is a contract owned by
[classdb.md](classdb.md#registration-pipeline): never defer this metadata to a
later initialization level or after another class derives from it.
`classdb_unregister_extension_class` drops the metadata with the class, so
`godot.deinitialize` needs no extra calls.

See [classdb.md](classdb.md) for the engine contract and the remaining class-level
surfaces (methods and static properties).

## Namespace detection

`isLikelyNamespace` is only a shape check: a zero-field, non-tuple struct. A
zero-field struct may still be a valid extension class, so registration checks
`reflect.isExtensionClass(Class)` first and only treats the struct as a namespace
when that check fails and `isLikelyNamespace` passes. Engine classes and other
types are rejected with a compile error.

## Virtual classes

`ClassOptions.is_virtual` is a tooling flag: the class keeps every callback and
stays instantiable by code. It requires `is_exposed = true`. `is_abstract` is
not implemented yet; it is the real no-instance mode. The engine behavior and
the asymmetry between the two flags are in
[classdb.md](classdb.md#d6-is_virtual-is-a-tooling-flag-only-is_abstract-removes-instances).
