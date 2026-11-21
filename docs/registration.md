# Registration

Registration is an optional convenience layer. The low-level pieces are usable
without `Registry`.

## Public surface

The facade exposes the registration layer as a module plus a convenience type:

```zig
godot.registration.Registry
godot.registration.ClassOptions
godot.registration.ClassRegistration
godot.registration.create_instance
godot.registration.instance
godot.registration.notification
godot.registration.property
godot.registration.virtuals

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
    depth: u8 = 2,
    // is_virtual, is_abstract later, once creation modes exist
};

pub const ClassRegistration = struct { // runtime, heap-stored per addClasses call
    instance_allocator: Allocator,
    gpa: ?Allocator = null,
    register_at_level: interface.InitializationLevel = .scene,
};
```

- `ClassOptions` is comptime: it selects callback shape (`auto_onready`,
  `auto_property_cleanup`), supplies the per-group `ClassCreationInfo6` flags
  (`is_exposed`, `is_runtime`, `icon_path`), and controls namespace traversal
  (`depth`).
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
- `is_runtime = true` (default) registers a runtime class; set it to false for
  editor/tool classes.
- `icon_path` is an editor-only `res://` icon path; `Registry` keeps its
  process-lifetime `String` and never frees it.
- `depth` controls namespace traversal: `1` registers direct extension classes
  only; `2` (default) also descends one nested namespace level.
- Different groups can have different allocators and registration levels.

## Grouped registration

The multi-class form is intentional:

```zig
registry.addClasses(
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
registry.addClasses(.{A}, .{}, .{ .instance_allocator = allocator });
```

`addClasses` allocates one `ClassRegistration` for the call. All classes in that call
share it. Use another call for another group.

The class name is `T.GodotClassName` when present, otherwise the short Zig type
name. Duplicate names are rejected. `addClasses` also accepts a namespace struct
and registers the extension classes it contains, expanding nested public
namespaces up to `ClassOptions.depth`.

`addClasses` returns errors such as `DuplicateClassName`. Report registration
failure from the entry symbol and fail extension startup.

## Scanned class groups

`build/class_files.zig` can generate a namespace module from files containing
`pub const Extends =`:

```zig
registry.addClasses(
    .{ @import("example.gen.zig") },
    .{ .auto_onready = true, .is_runtime = false },
    .{ .instance_allocator = allocator },
);
```

Use separate generated modules when groups need different `ClassOptions`,
allocators, or registration levels:

```zig
registry.addClasses(
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

- create-instance callback
- free-instance callback
- notification callback
- virtual lookup callback

Then they can call `classdb_register_extension_class6` themselves. No pooling,
arena, or instance-creation policy is forced by `Registry`. For property cleanup,
pass `true` to `FreeInstance`, or call `annotations.deinitPropertyFields` from
the free callback directly.

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
4. Initialize annotation fields (`annotations.initAnnotFieldsDefault`, the
   `OnReady` wrappers).
5. Initialize the `Base` marker field.
6. Run eager `Property` `.init` initializers (`annotations.initPropertyFields`).
7. Call the optional `InitCallback`.
8. Record the extension pointer and instance binding on the engine base
   (`setInstance`), only after all Zig-side initialization succeeded.
9. Send post-initialize notification only when `p_notify_postinitialize` is true.

The `.init` property initializers therefore run after the ordinary defaults,
`OnReady` wrappers, and `Base` marker are in place, and before user init code, so
`InitCallback` can rely on every property value already being assigned. They are
creation-time values, not OnReady: they never wait for scene-tree events, and
scene-dependent values use custom getters or `OnReady` fields.

If `InitCallback` returns an error, creation fails: the engine base and user
instance are destroyed without running `DeinitCallback` or property cleanup, even
when `auto_property_cleanup` is enabled. This includes values already assigned by
`Property` `.init` initializers, which run before `InitCallback`. Init code must
release anything it created, including those initialized values, before
returning the error.

Freeing:

1. Call the optional `DeinitCallback`.
2. When `FreeInstance` is built with `auto_property_cleanup = true`, call
   `annotations.deinitPropertyFields(T, instance)`: best-effort per-field cleanup
   (custom `.deinit` hook, then a value type's `deinit`, then a `RefCounted`
   reference release).
3. Destroy the user instance with `instance_allocator`.

`reflect.initFieldsDefault` only initializes fields that declare defaults.
Fields without defaults are the user's responsibility: provide a default,
initialize them with a `.init` initializer or in `InitCallback`, or accept that
they are undefined until set. The runtime does not force a zero-initialization
policy.

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

## Properties

When a class declares `Property` fields, registration installs the dynamic
`ClassCreationInfo6` property callbacks: `set_func`/`get_func` always, and
`get_property_list_func`/`free_property_list_func` only when at least one
property has non-zero usage. The property list is a lazy per-class static table
with process lifetime; it is never freed.

Property options also cover read-only dispatch and eager creation-time values:
`.read_only` keeps the getter but makes `set_func` reject engine sets (it cannot
be combined with a custom `.set`), and `.init` assigns the value during creation
(step 6 above). Neither changes lifetime policy: values must still start valid
and cleanup stays explicit. See [properties.md](properties.md) for the option
table and initializer rules.

Property values are not cleaned up on free by default: the free-instance callback
only calls `annotations.deinitPropertyFields` when `auto_property_cleanup` is
enabled. The default setter manages known managed builtins and `Variant`
(deinitializes the previous value on overwrite) and `RefCounted` references
(retain new, release previous); everything else is assigned as-is. Custom accessors are user code. See
[properties.md](properties.md) for the helper semantics and free order.

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
