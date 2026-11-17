# Annotations

Annotations are optional markers. Registration detects them at compile time and
adds behavior only when present. A class with no annotations still registers.

## Markers

### `Base(Extends)`

Marks the single field that stores the engine base pointer.

- At most one `Base` field is allowed.
- Required by auto-`OnReady`.
- `initBase` stores the constructed engine base into the marker.
- The marker provides a safe accessor and a debug guard.

### `OnReady(T, strategy)`

Marks a field for deferred initialization.

Supported strategies:

```zig
OnReady(Node, .{ .node = "./Child" })
OnReady(String, .{ .call = .{ .fromLatin1, .{"..."} } })
OnReady(u32, .{ .call = .{ f, .{} } })
```

- `.node` requires `T` to extend `Node`; it resolves a node path from the `Base`.
- `.call` invokes a function or a method resolved on the field's value type.
  Arguments may be plain values, `.owner`, `.base`, `{ .field = name }`, or a
  nested function receiving owner/base pointers. Generic functions must be
  wrapped with `annotations.callComptimeArg1`.
- `OnReady.get()` panics in safety-enabled builds when the value is unset. Use
  `getPtr()` / `getPtrConst()` when absence is valid.
- `initOnReadyFields(T, Base, owner, base)` initializes all marked fields.
- With `auto_onready = true`, registration initializes them on
  `post_enter_tree` if the class has a `Base` field.
- Users can skip auto mode and call `initOnReadyFields` manually.

### `InitCallback(T, f)`

Called during instance creation.

- Member form: receives `*T`, optional `Allocator`, optional `*Extends`.
- Static form: returns `T` or `!T`.
- Errors abort creation.
- The allocator is `AddClassData.gpa` when present, otherwise
  `create_allocator`.

### `DeinitCallback(T, f)`

Called before the user instance is freed.

- Must be a member function.
- May accept an `Allocator`.
- Must return `void`.
- Does not free the instance; `create_allocator.destroy` follows.
- Runs from the engine base destructor. Only release Zig-owned values;
  do not call methods on the engine base.

### `Override(godot_virtual_name, f)`

Provides a virtual implementation under an alternate Zig declaration name.

```zig
pub const CursorShape = godot.annotations.Override("_get_cursor_shape", cursorShape);

fn cursorShape(self: *const @This(), at_position: Vector2) i32 {
    return 0;
}
```

- The first argument is the exact engine virtual name, taken from
  `Virtual.Meta.godot_name`.
- Registration uses the override map before falling back to declaring a Zig
  method named after the generated virtual.
- The override function must match the generated virtual signature.
- This is useful when the Zig declaration name differs from the generated
  virtual name, or when the virtual name is generated with a conversion you do
  not want to depend on.

### `NotificationCallback(T, f)`

Called for every engine notification.

```zig
pub fn onNotification(self: *@This(), p_what: i32, p_reversed: bool) void
```

- Exactly three parameters.
- Does not free the instance.

## Annotation initialization

`annotations.initAnnotFieldsDefault(T, Base, owner, base)` initializes the
current default-initialized annotation fields. Today this is the `OnReady`
family; other markers have no field state. Add new default-initialized
annotation types here.

`reflect.initFieldsDefault` is separate: it initializes ordinary Zig field
defaults after `allocator.create` and is useful outside annotations.
