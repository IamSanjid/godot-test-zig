# ClassDB surfaces

Godot learns about an extension class from two different places: the
`ClassCreationInfo6` callback table it receives when the class is registered,
and the `classdb_register_extension_class_*` calls a library makes afterwards.
This page covers the class-level surfaces - methods, signals, integer constants,
and static properties - plus property groups, which are spliced into the
dynamic property list, and the two class flags `is_virtual`/`is_abstract`, which
look symmetric and are not.

Status: the callback-table surfaces and the first class-metadata slice are
implemented - signals, integer constants, the `is_virtual` flag, and the
per-class post-registration hook. Property groups and type-derived property
hints (enum, bitfield, Node/Resource object pointers, and wrapper or explicit
`Array`/`Dictionary` container metadata) are implemented on the dynamic property
list. Signal argument metadata and property metadata/value conversion use the
internal conversion layer; typed container wrappers are the `godot.collections`
module and are declared conversion types too. Methods are the next surface, then
`is_abstract`; both are designed here but not implemented yet.

## Two families

| Family | Mechanism | Needs a live Zig instance |
|---|---|---|
| instance surfaces | `ClassCreationInfo6` callbacks | yes |
| class-level metadata | `classdb_register_extension_class_*` after the class | no |

Instance surfaces are already implemented: creation, recreation on hot reload,
free, notifications, virtual overrides, and dynamic properties
(`set_func`/`get_func` plus `get_property_list_func`). They are installed once
per class and dispatched by the engine against an instance the extension created.

Class-level metadata is registered separately, per class, after
`classdb_register_extension_class6` returns. It describes the type, not a
value: what a method's signature is, what a signal carries, and which enum a
constant belongs to.

The distinction drives the whole design: an annotation that needs an instance
can be a field marker, and an annotation that describes the type is a
declaration marker.

## Engine contract

These are engine properties the design has to respect. Verified against the
local Godot 4.8-beta checkout in `zig-pkg/godot` (`version.py` reports 4.8.0
beta; the bundled `extension_api.json` is 4.8 beta2) - mainly `class_db.cpp`,
`object.cpp`, `gdextension.cpp`, and `gdtype.cpp`.
`gd_interface/gdextension_interface.h` documents the API shape locally.

- The class must exist first. Every metadata call fails with
  `"Attempt to register extension class <thing> 'x' for unexisting class 'y'."`
  unless the same `ClassLibraryPtr` already registered `y`.
- Signals and integer constants require the main thread and a class `GDType`
  that is still mutable. Registering a subclass finalizes the parent, so a
  class must register all of its metadata immediately after itself, before
  anything derives from it. Extension classes cannot derive from each other,
  so in practice this only constrains the order inside one `initialize`
  callback - and it is why the metadata must never be deferred to a later
  initialization level.
- The engine copies `MethodInfo`/`PropertyInfo` payloads. Argument arrays,
  names, and hint strings only have to be alive for the duration of the call,
  so this runtime builds them as stack temporaries per signal/constant. The two
  exceptions are `method_userdata` and `class_userdata`: both are stored
  verbatim and must outlive the registration.
- A property registered through `classdb_register_extension_class_property`
  resolves its setter and getter method names at registration time, so those
  methods must be registered first. In debug builds a missing setter/getter is
  an error and the property is dropped; in release builds it registers with a
  null accessor and fails only when used.
- A static property and a dynamic property with the same name are two separate
  entries. `Object::get_property_list` concatenates the ClassDB list and the
  `get_property_list_func` result without deduplicating, so the inspector shows
  both rows. No warning, no error.
- A signal that is not registered cannot be connected or emitted:
  `Object::connect` and `Object::emit_signal` check the class's signal map and
  fail with "nonexistent signal".
- Group and subgroup entries are read from the same property list the dynamic
  backend returns. The engine only inspects `name` (label), `hint_string`
  (prefix, optionally `"prefix,depth"`), and `usage` (`PROPERTY_USAGE_GROUP` or
  `PROPERTY_USAGE_SUBGROUP` exactly; no other flag ORed in).
- Integer constants are grouped by `enum_name`. An empty enum name makes a
  loose constant; a non-empty one creates or reuses a named enum. `is_bitfield`
  is last-registration-wins per enum, and a dotted enum name is truncated to
  the part after the dot.
- A method's `call_func` and `ptrcall_func` are both optional at registration
  and both mandatory in practice. GDScript compiles validated-call opcodes for
  a non-vararg native method with matching argument types, and
  `validated_call` falls through to `ptrcall_func` unconditionally - there is
  no ptrcall-to-call fallback in 4.7, so a method registered with only
  `call_func` crashes when called from a validated call site.
- `is_virtual` is stored but not consulted during instantiation. `ClassDB::is_virtual()` returns
  `can_instantiate(class) && class->is_virtual`, so a virtual class without a
  creation function does not even report as virtual, and instantiation never
  checks the flag.
- `is_abstract` is not stored either. It only suppresses inheritance of the
  parent's creation function at registration time; `ClassDB::is_abstract()`
  derives from the resulting null creation function. Passing a creation
  function together with `is_abstract = true` is therefore a broken
  combination: instantiation still fails, but the class does not report as
  abstract.
- `classdb_unregister_extension_class` deletes the class's method binds and
  drops its `GDType`, which owns properties, signals, constants, and virtual
  method records. No per-surface unregistration exists or is needed; cached
  `method_bind` handles become dangling.

## Decisions

### D1. The dynamic property backend stays the only property backend

Do not add static property registration for instanced classes.

A property registered statically is a second entry in the same name space, with
a method-name indirection for the setter and getter, a second source of truth
for hint/usage metadata, and a duplicate inspector row when the class also
declares the `Property` field. `Object::set`/`get` prefer the dynamic callback
anyway, so the static entry adds inspector noise rather than behavior.

The low-level call stays reachable through `godot.dispatch`.
`classdb_register_extension_class_property` and `..._property_indexed` are not
wrapped, and [properties.md](properties.md) now records that as a decision
rather than an unfinished task. Revisit only for a concrete case the dynamic
backend cannot express: indexed/array properties, or a class whose properties
must be visible in ClassDB before any instance exists.

### D2. Groups and subgroups are list entries, not registrations

Groups are inspector metadata for a property list, and the engine reads them
from the dynamic list, so the ClassDB group calls have no advantage over an
entry in the same table that already exists. Declare the section tree once per
class with `PropertyGroups`; [properties.md](properties.md#property-groups) owns
the contract:

```zig
pub const Groups = godot.annotations.PropertyGroups(.{
    .{
        .name = "Combat",
        .fields = .{ "health" },
        .groups = .{
            .{ .name = "Vitals", .fields = .{ "stamina" } },
        },
    },
});
```

- The marker is a class declaration, not a `Property` option: there is no
  `.group`, `.subgroup`, `.depth`, or prefix. The declaration name is free.
  A per-field option would derive section order and membership from field
  declaration order and repeat the name on every field; one class-level tree
  keeps the list authority in one declaration.
- The marker is authoritative when present: every visible `Property` field
  must be listed exactly once. Unknown fields, hidden fields, duplicate
  listings, and sections with no fields anywhere below them are compile errors.
- The entries are spliced into the dynamic `PropertyInfo` table: a section is
  `PROPERTY_USAGE_GROUP` at depth 0 or `PROPERTY_USAGE_SUBGROUP` above it,
  `type = NIL`, `hint = NONE`, and the depth rides in `hint_string` (for
  example `",1"`), leaving the prefix slot empty. No field is added and set/get
  never sees a section.
- Field entries take their `type` from `.type` or the declared type's engine
  Variant type, and their class name from the declared-type hint or the declared
  type's engine object representation; groups themselves add no conversion. See
  [properties.md](properties.md#property-groups).
- Names are verbatim engine strings and need not be unique. The engine labels
  sections by name, and duplicate names are legal.
- Field order inside a section is the listed order, and a section emits its
  direct fields before its child sections. Without the marker the dynamic list
  stays in field declaration order.

The static group calls (`..._property_group`, `..._property_subgroup`) are not
wrapped. A static group is appended to the ClassDB list, which always precedes
the dynamic block, so it cannot section dynamic properties, and it cannot carry
an indent depth through the C API.

### D3. Signals are required, not optional metadata

Before this work, an extension class cannot emit a signal that GDScript can
connect, because the engine only resolves signals from the class signal map.
Signal registration is therefore part of making an extension class usable, not
a documentation nicety. It costs no callback and no allocation policy: the
annotation carries a name and an argument list, and the engine copies it.

The argument list is declared in Zig types. The internal conversion layer
validates `.variant` support when the `Signal` marker is declared and derives
each argument's Variant type and engine class name for registration; `Variant`
is the one untyped argument and registers as `.nil`. Emit uses the same layer,
passing a borrowed Variant view where the representation allows one and an
owning Variant otherwise (released after dispatch). There is no separate signal
conversion rule, and the declaration is the only support gate. The naming,
exact-class receive contract, and unsupported cases are in
[signals.md](signals.md).

### D4. Methods are declared in a namespace, implemented as normal methods

Status: planned. No `Method` annotation or method registration is implemented
yet; the conversion layer it will use already exists.

Zig has no declaration attributes, so a method needs a companion declaration.
A flat companion declaration collides with the implementation's own name
(`pub fn get_health` and `pub const get_health` cannot coexist) and would force
a second name plus a string. A namespace struct avoids both:

```zig
pub const Methods = struct {
    pub const ping = godot.annotations.Method(.{ .arg_names = .{"target"} });
    pub const total_health = godot.annotations.Method(.{});
};

pub fn ping(self: *@This(), target: ?*godot.classes.core.Node) i32 { ... }
pub fn total_health() i32 { ... }
```

- The declaration name inside `Methods` is the engine name, converted with
  `naming.comptimeConvert(.godot, .method, ...)`; `.name` overrides it verbatim.
- The implementation is the declaration of the same name on the class, exactly
  like virtuals are resolved with `@hasDecl(T, name)`. No function value is
  passed, so no forward reference and no duplicate name is needed.
- Flags are derived, never written: `*T` self is an instance method, `*const T`
  self adds `METHOD_FLAG_CONST`, a missing self parameter makes it
  `METHOD_FLAG_STATIC`.
- Return type and argument types come from the Zig signature; the annotation
  only supplies the names Godot needs for GDScript keyword arguments.
- Vararg methods and default arguments are rejected in the first version. Zig
  function types do not carry parameter names, and comptime `Variant`
  construction is limited to scalars and nil, so default arguments would need a
  deferred registration-time Variant table. Neither is worth blocking on.

Both call paths are mandatory and land together:

1. `ptrcall_func` uses the internal conversion layer's ptrcall path. Arguments
   are borrowed raw values; a `RefCounted` return is an outgoing raw pointer, so
   the conversion write fills the engine slot's reference exactly like a virtual
   return. The shape is the same as the virtual callback apart from the leading
   `method_userdata`.
2. `call_func` converts borrowed argument Variants and writes an owning return
   Variant through the same layer's Variant path, and reports
   `CALL_ERROR_INVALID_ARGUMENT` instead of panicking.

Registered methods are called by the engine, so their results are outgoing like
virtual returns: use raw `?*T` for `RefCounted` results, not `Ref`. `Ref` results
belong to surfaces where *we* receive the engine's reference (engine-method calls
and property storage); see [ownership.md](ownership.md#the-model).

Registration will validate each parameter and the return against both paths
before registering; a signature that cannot support both is a compile error.
Custom types with a `Conversion` marker are accepted wherever both paths are
supported.

`call_func` is what `Object.call`/`callv`, `Callable`, signals, and dynamic
GDScript dispatch use. `ptrcall_func` is what a validated GDScript call uses,
and the engine has no ptrcall-to-call fallback, so registering one without the
other produces a method that crashes on one of the two call sites.

Static methods need `METHOD_FLAG_STATIC` for the same reason: the engine nulls
the instance handle for static calls and dereferences it otherwise. It is
derived, never written by the user.

### D5. Integer constants come from Zig enums and bitfields

A `Constants` marker wraps a struct of declarations, and the declaration shape
says what to register:

```zig
pub const ClassConstants = godot.annotations.Constants(struct {
    pub const MAX_HEALTH = 100;                        // loose constant
    pub const State = enum(i32) { idle, running = 3 }; // State.IDLE, State.RUNNING
    pub const Flags = bitpack struct(u32) {            // bitfield: Flags.FIRST = 1
        first: bool = false,
        second: bool = false,
        _pad0: u30 = 0,
    };
});
```

- The marker's declaration name is free; discovery collects every `Constants`
  marker on the class, appending entries in declaration order. The declaration
  shapes, name conversion, and compile-error rules are in
  [annotations.md](annotations.md#constantsdecls).
- The inspector hint for a `Property` comes from its Zig value type, not from
  this marker: an exhaustive enum with variants becomes `PROPERTY_HINT_ENUM`
  with `hint_string = "Idle:0,Running:3"`, and a bitpack struct with bool flag
  fields becomes `PROPERTY_HINT_FLAGS` with `"First:1,Second:2"`. Full rule:
  [properties.md](properties.md#property-hints).
- When the same class declares that exact enum/bitpack type in a `Constants`
  marker, the property additionally gets `class_name = "<Class>.<Name>"` and
  `PROPERTY_USAGE_CLASS_IS_ENUM` / `PROPERTY_USAGE_CLASS_IS_BITFIELD` (typed
  engine docs). An enum/bitfield declared on another class, or not declared at
  all, gets the hint string only - no `class_name` and no added usage bit.
- An explicit `.hint` or `.hint_string` wins and leaves the property without
  the automatic hint and enrichment; a hidden property gets no automatic hint.
- The hint registers nothing and adds no conversion rule. `Constants` already
  owns the enum/bitfield values; the property's `PropertyInfo.type` is still
  `.type` or the declared type's engine Variant type, and storage stays the
  declared int/enum/bitfield type. The hint only marks it for the inspector and
  docs. Contract: [properties.md](properties.md#enum-and-bitfield-hints).

### D6. `is_virtual` is a tooling flag; only `is_abstract` removes instances

The two flags look symmetric in the header and are not.

`is_virtual` does not change creation behavior at all. The engine stores it,
never consults it during instantiation, and reports `ClassDB::is_virtual()` as
`can_instantiate(class) && is_virtual`. Its only consumers are editor and
docs: the Create Node dialog, the resource picker, and default-value probing
skip such classes. A virtual class is still fully instantiable by code,
including GDScript. Two consequences:

- `.is_virtual` is a plain `ClassOptions` field. It needs no callback
  suppression and no annotation rejection.
- It requires a creation function and `is_exposed = true`: `is_virtual()` is
  `can_instantiate(class) && is_virtual`, and `can_instantiate` requires both an
  exposed class and a creation function. With `create_instance_func == null` the
  class stops reporting as virtual and `instantiate()` falls through to the
  parent's native creation function, producing an object of the wrong class.
  `Registry` always provides a creation function, so a compile error rejects
  `.is_virtual = true` with `.is_exposed = false`.

`is_abstract` is the real no-instance mode. It suppresses inheritance of the
parent's creation function at registration, and the engine then derives
abstractness from the resulting null creation function:

- `create_instance_func` and `free_instance_func` are null. No instance exists,
  so no instance callback is ever called: no property callbacks, no
  notification dispatch, no virtual lookup.
- Annotations that need an instance become compile errors: `Property` fields,
  `OnReady` fields, `Base` markers, `InitCallback`, `DeinitCallback`,
  `NotificationCallback`, `get_virtual_func`, and any `Methods` entry with a
  self parameter.
- What remains is the static surface: static methods, integer constants, and
  signals. This is also the useful case - a GDScript class can `extends` the
  abstract extension class, inherit that static surface, and `new()` is
  rejected at analysis time exactly as it would be for a native abstract class.
- Never install a creation function together with `is_abstract = true`. The
  engine would keep the class non-instantiable *and* stop reporting it as
  abstract, which is strictly worse than either mode alone. Setting both flags
  will be a compile error for the same reason, once `is_abstract` is
  implemented: `is_virtual()` already requires `can_instantiate`, which
  abstractness removes.

`classdb_register_extension_class_virtual_method` is deliberately not part of
this. It registers a *new* virtual that script classes may override, and its
engine body is debug-only, so it adds no runtime behavior. A class that wants
GDScript overrides needs that call plus `get_virtual_func` for instances, and
extension classes that would provide the overrides cannot be registered
descendants. Treat it as a separate feature with its own use case.

### D7. No generator changes

Codegen emits metadata for *engine* classes: `Virtual.{Required,Optional,Meta}`,
`MemberFunctions`, `StaticFunctions`, and enum/constant aliases. None of it
describes a user extension class, and the extension API does not need it to.
Method, signal, constant, and property-group metadata is authored in the user
class and read at comptime by the runtime, exactly like `Property` descriptors.
Bindgen and codegen stay untouched by this work, which is also the boundary in
[architecture.md](architecture.md).

## API surface

```zig
// implemented
godot.annotations.Signal("engine_name", .{ .{ "arg", i32 } }) // one flat signal declaration
godot.annotations.findSignals(T)         // signal discovery
godot.annotations.Constants(struct { ... }) // one constants marker
godot.annotations.findConstants(T)       // constants discovery
godot.annotations.ConstantEntry          // one discovered integer constant
godot.annotations.PropertyGroups(.{ ... }) // one property-section tree
godot.registration.classdb.postRegistrationCallback(T)
godot.registration.PostRegistrationCallback
godot.registration.ClassOptions.is_virtual

// planned
godot.annotations.Method(options)        // planned
godot.annotations.Constant(value, opts)  // optional override inside Constants
```

New files:

| File | Owns | State |
|---|---|---|
| `src/godot/annotations/signal.zig` | `Signal` marker, argument validation, discovery, typed `emit` | implemented |
| `src/godot/annotations/constants.zig` | `Constants` marker, constant/enum/bitfield discovery, and enum/bitfield hint metadata | implemented |
| `src/godot/registration/classdb.zig` | family gate, registration calls, copied argument metadata | implemented |
| `src/godot/conversion.zig` (internal) | declared-type support/metadata queries, Variant-path conversion, converter bridge; direct ptrcall slots via `ptrcall.zig` | implemented |
| `src/godot/annotations/method.zig` | `Method` marker, signature checks | planned |

The metadata queries these calls need come from the internal conversion layer:
it derives a declared type's engine Variant type and engine class name (a
`Conversion` marker's engine representation is followed), and it is the only
place that decides value conversion. Registration passes the declarations in and
receives metadata; it does not compose a class-name lookup at the call site.

Discovery follows the established shape: a `find*` function that scans the
class's type declarations, filters on `marker.Kind` first, re-derives the family
type and validates its shape, and returns a comptime slice in declaration order.
Every declaration marker uses that identity: `signal`, `constants`,
`property_groups`, and `override` for class-level declarations, plus the
callback kinds; `Conversion` is the type-attached `conversion` marker. `Init` is
not a marker. Identity and the 11-kind table are in
[annotations.md](annotations.md#marker-identity).

## Registration pipeline

`Registry` already stores one entry per class. It gained an optional erased
callback, specialized per class, that performs the class-level registration:

```zig
pub const RegisteredClass = struct {
    creation_info: interface.ClassCreationInfo6,
    data: *ClassRegistration,
    class_name: builtins.StringName,
    parent_class_name: builtins.StringName,
    post_registration_callback: ?PostRegistrationCallback,
};
```

`PostRegistrationCallback` is
`*const fn (interface.ClassLibraryPtr, *const builtins.StringName) void`. It
lives in `registration/classdb.zig` - next to the code that produces it - and is
re-exported by the registration module. The generated body composes the families
internally, so adding one never changes the field.

`godot.initialize` calls it directly after `classdb_register_extension_class6`,
for the same class, in the same initialization level:

```zig
dispatch(.classdb_register_extension_class6, .{ library(), &class.class_name, &class.parent_class_name, &class.creation_info });
if (class.post_registration_callback) |post_registration| {
    post_registration(library(), &class.class_name);
}
```

Order inside the per-class function:

1. methods (`..._method`), once they exist
2. integer constants (`..._integer_constant`)
3. signals (`..._signal`)

The implemented slice runs constants then signals; methods will be prepended
when they land. Constants and signals have no dependency on each other - only
static properties will need methods to run first. Signal argument names, Variant
types, and engine class names are expanded at comptime through the internal
conversion layer; the engine copies the resulting metadata, so no per-value
conversion happens during registration.

Groups and dynamic properties are part of `ClassCreationInfo6` and are not
registered here. `classdb_unregister_extension_class` drops the class and its
metadata, so deinitialization needs no per-surface calls.

No allocation is added: the tables are comptime values, and the engine copies
each `StringName`/`PropertyInfo`/`String` during the registration call, so
nothing class-level outlives it. The property list is the exception: the engine
holds its array until `free_property_list_func`, so it stays a process-lifetime
per-class static.

## Verification

Discovery, metadata expansion, and the conversion contract are covered by
compile-only checks and unit tests under `zig build test-godot`
(`tests/conversion.zig` pins declared-type support/metadata and the Variant path;
`tests/ptrcall.zig` pins the direct slot rules; the annotation tests pin
discovery and declaration errors). The optional
[`test-godot-live`](build.md#live-godot-tests) step verifies registration
metadata for the live fixture classes in a headless Godot process; other
class-level surfaces and editor-only behavior remain compile-only or manual.

## Non-goals

- no static property backend for instanced classes (D1)
- no generator or bindings changes (D7)
- no vararg methods or default arguments (D4)
- no `classdb_register_extension_class_virtual_method` (D6)
- no extension-to-extension inheritance, which Godot 4 does not support
- no automatic registration of a class's Zig methods, enums, or signals:
  discovery is declaration-marker driven, never inferred from the class body
