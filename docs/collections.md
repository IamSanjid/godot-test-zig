# Typed collections

`godot.collections` provides typed, owning wrappers over the engine `Array` and
`Dictionary` builtins:

```zig
godot.collections.Array(T)
godot.collections.Dictionary(K, V)
```

A wrapper owns one engine container handle and converts elements through the
internal conversion layer; see
[conversion.md](conversion.md). It is also a **declared conversion type**: a
`Conversion` marker maps it to the engine `builtins.Array`/`builtins.Dictionary`
on both the Variant and ptrcall paths, so a wrapper can be a
[`Property`](properties.md#typed-container-hints) value and a method or virtual
argument once those surfaces consume values. Each wrapper declares `Element`
(or `Key`/`Value`) so container hints derive automatically.

Status: the wrappers, their declared conversion, engine typing metadata,
wrapper-typed properties with auto hints, and headless live coverage are
implemented. Unit coverage is compile-only in `src/godot/tests/collections.zig`
and in the hint/conversion analysis of `tests/annotations/property.zig`,
`tests/annotations/signal.zig`, and `tests/conversion.zig`; the live fixture is
described in [Live coverage](#live-coverage).

## Representation

Each wrapper is a normal Zig value type in
[src/godot/collections.zig](../src/godot/collections.zig) with one public
`inner: builtins.Array`/`builtins.Dictionary` handle, an `Element` (or
`Key`/`Value`) type declaration for the plain element types, and a private
`Conversion` marker whose declaration name is free (`GodotConversion` here).
`annotations/property_hint.zig` reads the declarations for hints; conversion
itself needs only the marker.

- A wrapper value owns exactly one engine handle. Copying the wrapper aliases
  that handle; only one copy may be deinitialized. Move it by assignment and
  leave the source alone.
- The wrapper has no engine object identity and no engine class name. On a
  conversion path it is the engine container value; otherwise it never appears in
  the engine ABI. `init()` returns it by value and `deinit()` takes `*Self`.
- `T`, `K`, and `V` are declared Zig types for element conversion. They describe
  the elements the wrapper converts, not a compile-time guarantee about the
  engine handle; see [Typing](#typing).
- `Variant` as the element type or as a dictionary side means untyped.

## Declared conversion type

The wrapper's marker makes it a first-class declared type for the internal
conversion layer:

- Both paths are supported: the Variant path carries the ordinary
  `.array`/`.dictionary` Variant, and the ptrcall path carries the engine
  container handle. `Dictionary(K, V)` reports `.dictionary`, `Array(T)`
  `.array`.
- The engine type is the directly supported engine container builtin, and the
  engine class name is empty because a container is not an object. There is no
  chain: the wrapper is one declared type and the builtin is its engine
  representation.
- The conversion bridge functions are private adapters; user code keeps the
  explicit `init`/`fromEngine`/`toEngine`/`clone` surface. The Variant path
  builds an owning Variant from another owned handle and then releases that
  intermediate; the ptrcall path hands the handle to the engine slot. The
  wrapper's own handle is untouched either way.
- The bridge's reverse direction **retains**: the Variant path releases its
  intermediate after decoding, and the ptrcall path passes a borrowed slot
  value. A decoded wrapper therefore owns one reference its consumer must release
  through `deinit`; nothing releases decoded values automatically. See
  [conversion.md](conversion.md#ownership-direction) and
  [ownership.md](ownership.md).
- Public `fromEngine` takes over an already owned handle: the caller passes a
  handle it owns and must not release it separately. It adds no reference.

## Ownership

| Member | Contract |
|---|---|
| `init()` | Creates a new empty engine container and types it; the returned wrapper owns it. |
| `deinit()` | Releases the owned handle. The wrapper is invalid afterwards. |
| `fromEngine(engine)` | Takes over an already owned handle. The caller must not release it separately. Other handles to the same container may exist; they are reference-counted separately. The wrapper does not change the handle's typing and adds no reference. |
| `toEngine()` | Returns another owned handle to the same container. The caller releases it (`builtins.Array.deinit`/`builtins.Dictionary.deinit`) or hands it to another owner, such as a builtin-typed property assignment. |
| `clone()` | New owning wrapper over an independent shallow copy (`duplicate`). |
| `.inner` | The owned handle. Do not release it while the wrapper is alive. |

Engine `Array` and `Dictionary` values are reference types: assigning or copying
a handle shares the same container, and mutations through one handle are visible
through every handle.

- `Array.fromArray` and `Dictionary.fromDictionary` are the engine copy
  constructors that add a reference, so `toEngine()` shares contents with the
  wrapper while giving the caller a separately released handle. Releasing either
  handle leaves the other valid.
- `clone()` is the independent-copy operation: it uses `duplicate(.{})`, which
  copies the outer container (and its typing) while nested containers and
  objects stay shared. `clone()` is not `toEngine()`.
- The engine `array_ref` operation is deprecated since Godot 4.5 and missing
  from `disable_deprecated` builds, so no `Array.ref` is exposed; the copy
  constructor replaces it.

`toEngine` is the hand-off operation for builtin-typed property storage; a
wrapper-typed field takes the wrapper itself (see
[Property values](#property-values)):

```zig
// Builtin-typed storage: hand over another owned handle.
var numbers = godot.collections.Array(i32).init();
defer numbers.deinit();
numbers.append(1);
self.numbers_builtin.value = numbers.toEngine();

// Wrapper-typed storage: move the wrapper; do not deinit it afterwards.
var owned = godot.collections.Array(i32).init();
owned.append(1);
self.numbers.value = owned;
```

## Typing

`init()` creates the empty engine container and applies the typing metadata
before returning. `fromEngine`, `toEngine`, the conversion adapters, and
`clone()` never retype a container.

- Array: the element's engine Variant type is the array element type, and its
  engine class name the class name for object elements. A `Variant` element is
  untyped, so no `set_typed` call is made.
- Dictionary: the key and value sides are handled independently. A `Variant`
  side is untyped; when both sides are `Variant`, no `set_typed` call is made at
  all.

The engine accepts `set_typed` only on a container that is empty, not read-only,
not shared with another user, and not already typed; the type cannot change
afterwards. That is why `init()` sets it eagerly, and why `fromEngine` and the
copy operations do not.

Element and side types are validated at compile time by the conversion layer, so
only Variant-convertible types are accepted. Because the metadata comes from the
same declared type, a custom type with a `Conversion` marker works as an element
or side type.

Typing is engine container state, not part of the wrapper's declared type. The
lazy `get() ?T` contract is unchanged: neither `fromEngine` nor either
conversion path verifies that a taken-over handle's element typing matches
`T`/`K`/`V`. An element `get` returns null when decoding fails, while
`append`/`set`/`put` encode through the declared type and leave engine-side type
validation to the engine.

## Property values

A wrapper is a struct value type declaring `deinit`, so it is non-trivial for
[property ownership](properties.md#ownership-modes): a wrapper-typed `Property`
declares `.set` and `.deinit` explicitly. `.best_effort` on both is the
leak-free preset, because the setter deinitializes the replaced wrapper and the
cleanup mode releases it at free time.

```zig
numbers: godot.annotations.Property(godot.collections.Array(i32), .{
    .usage = .exported,
    .set = .best_effort,
    .deinit = .best_effort,
}) = .init(undefined),
```

- The field stores the wrapper itself (`value: godot.collections.Array(i32)`),
  not the bare builtin. `PropertyInfo.type` is `.array`/`.dictionary` from the
  wrapper's engine type, and the property class name is empty.
- Container hints derive automatically from `Element`/`Key`/`Value`; no
  `.element`/`.key`/`.value` options are needed. Explicit container options
  remain available for `builtins.Array`/`builtins.Dictionary` storage and merge
  per side with a wrapper's declarations (an explicit side wins, the other side
  keeps the wrapper's).
- Moving a wrapper into the field transfers the handle:
  `self.numbers.value = numbers;` leaves `numbers` moved-from, so it must not be
  deinitialized afterwards. `.Init(godot.collections.Array(i32).init, .{})` also
  works: initializers store an owned value directly.
- On engine set, the Variant path produces an owned wrapper and the declared
  `.set` mode stores it, releasing the previous wrapper. On engine get, the
  Variant path copies the stored wrapper into an owning Variant; the field keeps
  its handle. The hint never retypes an assigned container, so create typed
  containers with `init()` or `setTyped`/`setTypedAs`.
- Free-time cleanup is opt-in per class: call
  `annotations.deinitPropertyFields` from `DeinitCallback` or enable
  `ClassOptions.auto_property_cleanup`. A wrapper field left `undefined` must not
  reach cleanup.

## `Array(T)`

| Member | Contract |
|---|---|
| `init() Self` | Empty array, typed from `T`. |
| `deinit(*Self)` | Release the handle. |
| `fromEngine(builtins.Array) Self` | Takes over an already owned handle without changing its typing or adding a reference. |
| `toEngine(*const Self) builtins.Array` | Another owned handle to the same array (shared reference semantics). |
| `clone(*const Self) Self` | New wrapper over an independent shallow copy (`duplicate`). |
| `len(*const Self) usize` | Engine size. |
| `append(*Self, value: T)` | Convert `value` to a temporary Variant and append it. The temporary is released; the caller keeps `value`. |
| `get(*const Self, index: usize) ?T` | Engine copy at `index`, decoded as `T`; null when decoding fails. For an optional `T` the result is doubly optional: outer null is a decode failure, inner null is a nil value. Declared-value ownership follows the Variant path: owned for owning builtins and borrowed for object pointers. |
| `set(*Self, index: usize, value: T)` | Convert and write the slot; the engine keeps its own copy. |

## `Dictionary(K, V)`

| Member | Contract |
|---|---|
| `init() Self` | Empty dictionary, typed from the `K` and `V` sides. |
| `deinit(*Self)` | Release the handle. |
| `fromEngine(builtins.Dictionary) Self` | Takes over an already owned handle without changing its typing or adding a reference. |
| `toEngine(*const Self) builtins.Dictionary` | Another owned handle to the same dictionary (shared reference semantics). |
| `clone(*const Self) Self` | New wrapper over an independent shallow copy (`duplicate`). |
| `len(*const Self) usize` | Engine size. |
| `put(*Self, key: K, value: V) bool` | Set an entry; false when the engine rejects the key or value. |
| `get(*const Self, key: K) ?V` | Decode the value for `key`; null when the key is missing or decoding fails. For an optional `V` the result is doubly optional: outer null is missing/mismatch, inner null is a nil value. |
| `contains(*const Self, key: K) bool` | Engine `has`. |
| `erase(*Self, key: K) bool` | Engine `erase`. |

The wrappers expose only the common operations above. While the wrapper is
alive, use the public `inner` handle for the rest of the generated builtin API
(`duplicate`, `keys`, `merge`, `resize`, ...).

## Engine metadata

The generated builtins expose the metadata operations the wrappers use as
methods on the container; they are also usable directly on a container you
create:

```zig
var array = godot.builtins.Array.init();
array.setTyped(i32, null);
array.setTypedAs(.int, null, null);

var dict = godot.builtins.Dictionary.init();
dict.setTyped(godot.builtins.String, i32, null, null);
dict.setTypedAs(.string, null, null, .int, null, null);
```

- `setTyped` is the typed Zig form. It uses `godot.builtins.Variant.typeFor(T)`
  and `reflect.classNameOf(T)`, so it covers directly supported types only: a
  type with a `Conversion` marker is not followed. A type without a Variant
  representation is a compile error; `Variant` means untyped, so an array
  `setTyped(Variant, ...)` is a no-op and a dictionary with both sides `Variant`
  is a no-op. The optional `script` argument is forwarded only for an `object`
  element/side; it is ignored otherwise.
- `setTypedAs` is the raw engine form. The collection wrappers use the declared
  type's engine Variant type and engine class name through the internal
  conversion layer, so they do follow converters. The wrappers pass no script; a
  script class is not part of their metadata.
- The C interface dereferences every metadata pointer, so null `class_name` and
  `script` arguments become an empty `StringName` and a nil Variant.
- The same engine constraints apply: empty, not read-only, unshared, and
  untyped; a class name is only valid with the `object` Variant type, and a
  script is only valid together with a class name.
- The generated builtins also read the metadata back:
  `Array.getTypedBuiltin`, `Array.getTypedClassName`, `Array.getTypedScript`,
  and the `Dictionary` key/value variants of those.

## Live coverage

- `src/godot/tests/collections.zig` is compile-only analysis over scalar,
  `String`, object, `Variant`, and converter elements and dictionary sides. It
  also pins that every wrapper reports both conversion paths through the marker.
  It is imported by `all.zig`.
- `tests/annotations/property.zig` covers wrapper-typed property descriptors:
  `Array(i32)` derives `"2/0:"`, `Array(?*Node)` derives `"24/34:Node"`, a
  converter element resolves through its engine representation (an enum-engine
  converter keeps the enum hint string), and `Dictionary(String, i32)` derives
  `"4/0:;2/0:"`; explicit hints win, an explicit container side merges with the
  wrapper's other side, and a non-type `Element` declaration is ignored.
  `tests/annotations/signal.zig` covers a wrapper signal argument (`.array`
  Variant metadata), and `tests/conversion.zig` analyzes the Variant path on
  wrapper types.
- The live extension registers `LiveTypedNode` with wrapper-typed exported
  properties `numbers` (`Array(i32)`), `resources` (`Array(?*LiveResource)`), and
  `scores` (`Dictionary(String, i32)`), plus owned `Ref(Resource)` properties
  `resource` and `resource_copy`. Its creation callback fills wrappers and moves
  them into the fields; `DeinitCallback` cleans the fields up.
- `godot-test/tests/collections.gd` checks the auto-derived hint metadata,
  engine-side typing (`get_typed_builtin`, `get_typed_class_name`, typed
  dictionary key/value types), and set/get round-trips for containers and `Ref`
  properties. See [build.md](build.md#live-godot-tests).
- The example scaffold uses the same form:
  `test_node2: Property(godot.collections.Array(*TestResource), ...).Init(.init, .{})`
  in `src/example/TestNode.zig`.

## Not in this version

- No automatic release of decoded container arguments: wrappers have a ptrcall
  representation through their marker, but no method surface consumes a wrapper
  argument yet. Virtual signatures are engine-defined, so converters cannot
  appear there. When methods land, the decoded wrapper owns one reference and the
  method adapter must release it through `deinit`; that argument-release policy
  is deferred with methods.
- No automatic typing of a container assigned through an engine property set:
  the hint is metadata, and the stored container keeps its own typing. Create
  typed containers with `init()` or `setTyped`/`setTypedAs`.
- No per-element inline inspector UI. The engine's default array and dictionary
  editors use the property hint metadata; custom inline editing needs an
  `EditorInspectorPlugin`.
- No iterator, sort, or batched element-conversion helpers; element conversion is
  lazy per access. Use `.inner` for the rest of the generated builtin API.
- No chain conversion: the wrapper's engine type must stay the engine container
  builtin. Container element conversion is composed by the wrapper, not by the
  conversion layer.

## Related

- [properties.md](properties.md#typed-container-hints) - the wrapper-typed
  `Property` form, the container options, and the hint strings they derive.
- [properties.md](properties.md#ownership-modes) - why wrapper fields declare
  `.set`/`.deinit`.
- [conversion.md](conversion.md) - the declared-type conversion model and
  converter ownership rules.
- [ownership.md](ownership.md) - the `Ref`/`Owned`/borrow model; a decoded
  wrapper owns one reference like a `Ref`.
- [variants.md](variants.md#typed-containers) - Variant ownership and the engine
  metadata relationship.
- [build.md](build.md#live-godot-tests) - the live Godot test.
