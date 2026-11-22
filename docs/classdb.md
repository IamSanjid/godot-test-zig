# ClassDB surfaces

Godot learns about an extension class from two different places: the
`ClassCreationInfo6` callback table it receives when the class is registered,
and the `classdb_register_extension_class_*` calls a library makes afterwards.
This page covers the second group - methods, signals, integer constants,
property groups, and static properties - plus the two class flags
`is_virtual`/`is_abstract`, which look symmetric and are not.

Status: the callback-table surfaces and the first class-metadata slice are
implemented - signals, integer constants, the `is_virtual` flag, and the
per-class post-registration hook. Methods, property groups, and `is_abstract`
are designed here but not implemented yet.

## Two families

| Family | Mechanism | Needs a live Zig instance |
|---|---|---|
| instance surfaces | `ClassCreationInfo6` callbacks | yes |
| class-level metadata | `classdb_register_extension_class_*` after the class | no |

Instance surfaces are already implemented: creation and free, notifications,
virtual overrides, and dynamic properties (`set_func`/`get_func` plus
`get_property_list_func`). They are installed once per class and dispatched by
the engine against an instance the extension created.

Class-level metadata is registered separately, per class, after
`classdb_register_extension_class6` returns. It describes the type, not a
value: what a method's signature is, what a signal carries, which enum a
constant belongs to, where an inspector section starts.

The distinction drives the whole design: an annotation that needs an instance
can be a field marker, and an annotation that describes the type is a
declaration marker.

## Engine contract

These are engine properties the design has to respect. Verified against the
Godot `4.7` branch sources (`class_db.cpp`, `object.cpp`, `gdextension.cpp`,
`gdtype.cpp`); `gd_interface/gdextension_interface.h` documents the API shape
locally.

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
entry in the same table that already exists. Model them as additive `Property`
options, as [properties.md](properties.md#options) anticipated:

```zig
// planned: `.group` and `.subgroup` are not implemented yet.
health: godot.annotations.Property(i32, .{
    .usage = .exported,
    .group = "Combat",
    .subgroup = "Vitals",
}) = .init(100),
```

- A `.group` emits a `PROPERTY_USAGE_GROUP` entry immediately before its
  anchor property, then the property itself.
- A `.subgroup` emits a `PROPERTY_USAGE_SUBGROUP` entry and requires a group
  already emitted earlier in the same class.
- The anchor must be a listed property (non-zero usage). A group attached to a
  hidden property would put a section in front of nothing; reject it.
- `.group = "Combat"` is shorthand for `.{ .name = "Combat", .prefix = "" }`.
  The struct form adds `.prefix` and `.depth`. When the prefix is non-empty the
  anchor property name must match it, otherwise the group would exclude its own
  anchor.
- A group is list metadata, not a stored value: it adds no field and never
  dispatches through set/get.

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

Signals also get a typed emit helper, because `Object.emit_signal` takes a
`StringName` plus a tuple of owning Variants. The declaration naming, the
argument conversion rules, and the exact-class receive contract are locked in
[signals.md](signals.md).

### D4. Methods are declared in a namespace, implemented as normal methods

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

1. `ptrcall_func` reuses `abi.readArgument`/`writeReturn` and the RefCounted
   `Ref<T>` rules already proven by the virtual callback; the shapes are
   identical apart from the leading `method_userdata`.
2. `call_func` converts borrowed argument Variants with `Variant.asDeclared`,
   writes an owning `Variant.initDeclared` return, and reports
   `CALL_ERROR_INVALID_ARGUMENT` instead of panicking.

`call_func` is what `Object.call`/`callv`, `Callable`, signals, and dynamic
GDScript dispatch use. `ptrcall_func` is what a validated GDScript call uses,
and the engine has no ptrcall-to-call fallback, so registering one without the
other produces a method that crashes on one of the two call sites. A signature
that cannot support both is a compile error, not a partial registration.

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
- Only enum and bitfield declarations can feed the inspector: a property whose
  value type is one of them should get `PROPERTY_HINT_ENUM` plus
  `hint_string = "Idle:0,Running:3"`, and, for docs and GDScript typing,
  `PROPERTY_USAGE_CLASS_IS_ENUM` with `class_name = "<Class>.<Enum>"`. That
  wiring is additive `Property` metadata for phase B, not part of the
  registration call.

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
Method, signal, and constant metadata is authored in the user class and read at
comptime by the runtime, exactly like `Property` descriptors. Bindgen and
codegen stay untouched by this work, which is also the boundary in
[architecture.md](architecture.md).

## API surface

```zig
// implemented
godot.annotations.Signal("engine_name", .{ .{ "arg", i32 } }) // one flat signal declaration
godot.annotations.findSignals(T)         // signal discovery
godot.annotations.Constants(struct { ... }) // one constants marker
godot.annotations.findConstants(T)       // constants discovery
godot.annotations.ConstantEntry          // one discovered integer constant
godot.registration.classdb.postRegistrationCallback(T)
godot.registration.PostRegistrationCallback
godot.registration.ClassOptions.is_virtual

// planned
godot.annotations.Method(options)        // phase C
godot.annotations.Constant(value, opts)  // optional override inside Constants
```

New files:

| File | Owns | State |
|---|---|---|
| `src/godot/annotations/signal.zig` | `Signal` marker, argument validation, discovery, typed `emit` | implemented |
| `src/godot/annotations/constants.zig` | `Constants` marker, constant/enum/bitfield discovery | implemented |
| `src/godot/registration/classdb.zig` | family gate, registration calls, copied argument metadata | implemented |
| `src/godot/annotations/method.zig` | `Method` marker, signature checks | phase C |

The type queries these calls need are not in this table: a declared type's
`Variant` type comes from `builtins.Variant.typeFor` (registration raises the
declaration-named compile error itself), an object type's engine class name from
`reflect.classNameOf`, and value conversion from
`Variant.initDeclared`/`asDeclared`.

Discovery follows the established shape: a `find*` function that scans the
class's type declarations, filters by marker identity, and returns a comptime slice
in declaration order. Declaration markers do not use `marker.Kind`; that enum
stays reserved for field wrappers, and identity comes from re-derivation as in
`annotations/override.zig`.

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
static properties will need methods to run first.

Groups and dynamic properties are part of `ClassCreationInfo6` and are not
registered here. `classdb_unregister_extension_class` drops the class and its
metadata, so deinitialization needs no per-surface calls.

No allocation is added: the tables are comptime values, and the engine copies
each `StringName`/`PropertyInfo`/`String` during the registration call, so
nothing class-level outlives it. The property list is the exception: the engine
holds its array until `free_property_list_func`, so it stays a process-lifetime
per-class static.

## Implementation phases

Each phase is independently testable and leaves the tree green.

### Phase A - surface plumbing, signals, constants (implemented)

Landed as:

1. `annotations/signal.zig`: `Signal("engine_name", .{ .{ "arg", i32 } })` with
   argument-shape and duplicate-name checks, `findSignals`, and the marker's own
   typed `emit`.
2. `annotations/constants.zig`: the `Constants(decls)` marker expands integer
   declarations, `enum` variants, and `bitpack struct` flags. Bit positions are
   read from the real bitpack layout, so padding anywhere in the declaration is
   handled, and a duplicate `(enum, name)` pair is a compile error.
3. The annotations facade re-exports `ConstantEntry`; `findSignals` returns the
   marker types. There is no aggregate module: the family list and its ordering
   live in `registration/classdb.zig`, which has to know them anyway.
4. `registration/classdb.zig`: `postRegistrationCallback(T)` and the
   constant/signal dispatch calls, with per-call argument metadata that the
   engine copies.
5. `registration/` resolves the `PropertyInfo.type` from `Variant.typeFor` and
   raises the declaration-named error itself; `reflect` gained `classNameOf` for
   the `PropertyInfo.class_name` side.
6. `Registry`: `post_registration_callback`, `ClassOptions.is_virtual`, and the
   `.is_virtual`/`.is_exposed` pairing check.
7. Coverage: compile-only checks in every module, discovery unit tests that run
   under `zig build test-godot`, and an example class that declares two signals,
   a loose constant, an enum, and a bitfield.

Why first: metadata only. No callback, no marshalling, no ownership question,
and it proves the registration order and the per-class pointer.

### Phase B - groups and subgroups

`Property` options `.group`/`.subgroup`, entries spliced into the existing
`PropertyInfo` table, validation (anchor listed, prefix matches anchor,
subgroup after group), plus enum property wiring from D5
(`PROPERTY_HINT_ENUM`, `class_is_enum`, `class_name`). This is where the
`option_keys` list and the "unknown option" message in
`annotations/property.zig` should get a single source so the diagnostics cannot
drift.

### Phase C - methods

`annotations/method.zig`, `ClassMethodInfo` construction, argument
`PropertyInfo`/`ClassMethodArgumentMetadata` derivation, and both call adapters.
Instance and static methods land together because the static bit is derived
from the same signature; both call paths land together because a method
registered with only one of them crashes on the other call site.

The varcall adapter converts through `Variant.initDeclared`/`asDeclared` - the
same operations properties, signals, and callables use - while the ptrcall
adapter keeps `abi.zig`'s slot rules. A Zig closure
([callables.md](callables.md)) reuses the same conversion for its arguments and
return.

This is the first phase that executes user code from an engine call, so it
needs a real-engine test, not only analysis. A signature the adapters cannot
marshal (vararg, unsupported argument type) must fail at comptime rather than
produce a partial `MethodInfo`.

### Phase D - abstract classes

`ClassOptions.is_abstract`, creation/free suppression, `get_virtual_func` and
instance-surface rejection, pair validation with `is_virtual`, and the
remaining static surface. The class still registers normally, so the phase A
path must not assume an instance exists.

### Phase E - optional, deferred

Static properties (D1), `classdb_register_extension_class_virtual_method`,
default arguments, varargs, indexed properties, `property_can_revert`.

## Verification

The engine-facing behavior cannot be proven by analysis; each phase that adds
a call needs a real-editor check. The minimum matrix:

| Check | Phase |
|---|---|
| GDScript sees a constant: `MyClass.MAX_HEALTH`, `MyClass.State.RUNNING`, bitfield flag | A |
| GDScript connects and emits a registered signal, with typed arguments | A |
| Unregistered signal still fails to connect (the behavior being fixed) | A |
| `is_virtual` class is hidden from Create Node but still constructible by code, and never produces an object of the parent class | A |
| Unregister at deinitialize leaves no dangling metadata | A |
| Inspector shows group/subgroup sections in the right order, prefix filtering | B |
| Enum-typed property shows a dropdown, docs show the enum | B |
| Instance and static methods work through a validated call and through `call`/`callv`, with and without return | C |
| Wrong argument type returns a call error instead of crashing | C |
| `is_abstract` class cannot be instantiated by GDScript or `instantiate`, and its instance annotations are rejected | D |

Discovery (names, argument shapes, enum and bitfield expansion, duplicate
checks) is covered by unit tests under `zig build test-godot`. Compilation and
generated-tree analysis are gated by `zig build` and `zig build test-godot`.
Everything engine-facing is still compile-only analysis until a runtime test
harness exists, so each phase keeps the manual checklist above.

## Non-goals

- no static property backend for instanced classes (D1)
- no generator or bindings changes (D7)
- no vararg methods or default arguments (D4)
- no `classdb_register_extension_class_virtual_method` (D6)
- no extension-to-extension inheritance, which Godot 4 does not support
- no automatic registration of a class's Zig methods, enums, or signals:
  discovery is declaration-marker driven, never inferred from the class body

## Open questions

- Whether a method may share a name with an engine method of the parent class.
  Registration is per-class, but name lookup in ClassDB walks the hierarchy, so
  a colliding name may shadow or error.
- Whether `p_instance` is always the extension instance for a GDScript class
  that extends an extension class. If it is not, instance methods on such a
  class need a guard instead of an unconditional pointer cast. This is the
  highest-risk unknown in phase C.
- Whether the duplicate-method error (`"Method already bound"`) is debug-only.
  If it is, a duplicate name in one class silently drops a bind in release.
- Whether the first-use initialization of `ListStorage` needs synchronization.
  It relies on being initialized before cross-thread use; method tables will
  add the same static pattern, so decide it once.

## Review: the current `Property` annotation

The property layer is the reference this work should copy, with a few additions.

Keep:

- Field-as-type. Storage and metadata stay together, discovery is a field scan,
  and there is no name dictionary. Methods and signals go the other way only
  because they have no storage.
- Marker identity with re-derivation (`F == Property(F.PropertyFor, F.options)`)
  rather than a lookalike-prone shape check.
- Comptime option validation with actionable messages, including the unknown
  option list and the required `.usage` check.
- Comptime descriptor table plus a lazy process-lifetime `PropertyInfo` table.
  Method, signal, and constant metadata should be built the same way.
- `.init` as creation-time assignment, separate from engine dispatch and from
  `OnReady`. The same discipline applies to class-level metadata: it is written once
  during registration and never on a value path.
- Explicit lifetime: no implicit cleanup, `auto_property_cleanup` opt-in.

Change or watch:

- `option_keys` in `annotations/property.zig` is a manual copy of the accepted
  keys, repeated in the "Supported options" error text. It will drift as
  `.group`, `.subgroup`, and the enum wiring arrive; derive both from one list.
- `PropertyDescriptor` has no hint/class-name slot for enums. The enum wiring
  in phase B needs a `class_name` source that is not an object target, which
  means the class-name source must generalize from `reflect.classNameOf` (object
  targets only) to object targets, registered enums, or empty.
- The property list is the only static `PropertyInfo` table today. Method
  tables will be a second copy of the same lazy skeleton (`class_names`,
  `hint_strings`, `infos`, `initialized`); extract one registration-local table
  then, not before.
- `descriptors(T)` re-normalizes every field's options on each call through
  `isPropertyField`. It is fine at current sizes and already guarded by an
  eval branch quota; do not make it the pattern for method tables, which should
  normalize once when the class-level metadata is collected.
- The dynamic backend's `set_func` matches names by linear scan over inline
  descriptors. Method and signal dispatch does not have that cost - the engine
  dispatches by `MethodInfo` pointer - so do not generalize the scan.

