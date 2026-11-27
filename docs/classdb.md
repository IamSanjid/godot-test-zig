# ClassDB surfaces

Godot learns about an extension class from two different places: the
`ClassCreationInfo6` callback table it receives when the class is registered,
and the `classdb_register_extension_class_*` calls a library makes afterwards.
This page covers the class-level surfaces - methods, signals, integer constants,
and static properties - plus property groups, which are spliced into the
dynamic property list, and the two class flags `is_virtual`/`is_abstract`, which
look symmetric and are not.

Status: the callback-table surfaces and the class-metadata slice are implemented
- signals, integer constants, methods, the `is_virtual` flag, and the per-class
post-registration hook. Property groups and type-derived property hints (enum,
bitfield, Node/Resource object pointers, and wrapper or explicit
`Array`/`Dictionary` container metadata) are implemented on the dynamic property
list. Signal and method argument metadata and property metadata/value conversion
use the internal conversion layer; typed container wrappers are the
`godot.collections` module and are declared conversion types too. Method
declarations, discovery, validation, registration, and both call adapters are
implemented and live-verified; `is_abstract` is the next surface.

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
  `call_func` crashes when called from a validated call site. `validated_call_func`
  is never needed for that reason; this runtime leaves it null.
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

### D4. Methods are declared in one `Methods` container

Status: implemented end to end. `Method`/`Methods` declarations, discovery,
signature validation, ClassDB registration, and both call adapters are in
place; the live fixture and `godot-test/tests/methods.gd` exercise the two call
paths against a headless engine.

Zig has no declaration attributes, so a method needs a companion declaration. A
flat marker cannot share the implementation's name (`pub fn ping` and
`pub const ping` cannot coexist), so the markers live in a `Methods` tuple whose
declaration name is a free handle; a class may split them across containers:

```zig
pub const RegMethods = godot.annotations.Methods(.{
    godot.annotations.Method(.ping, .{ .arg_names = .{"target"} }),
    godot.annotations.Method(.version, .{ .is_static = true }),
    godot.annotations.Method(helperImpl, .{ .name = "helper", .arg_names = .{"value"} }),
});

pub fn ping(self: *@This(), target: ?*godot.classes.core.Node) i32 { ... }
pub fn version() i32 { ... }
fn helperImpl(self: *@This(), value: i32) void { ... }
```

- `Methods` takes a tuple of `Method` markers; discovery flattens every
  container in declaration order. A `Method` marker outside a container is not
  discovered.
- `Method(the_method, options)` accepts two implementation forms:
  - an enum literal names the class declaration of that name (resolved through
    `@hasDecl`/`@field`), with the tag converted by
    `naming.comptimeConvert(.godot, .method, ...)` as the default engine name;
    only `pub fn` declarations are visible across modules, so an enum-literal
    implementation must be public;
  - a direct function reference keeps that function value and requires `.name`,
    because there is no Zig declaration name to convert. A direct reference may
    be a private function.
- Options: `.name` is the verbatim engine name; `.arg_names` is an optional
  tuple of engine argument names in engine order and must match the engine
  argument count; `.is_static` defaults to false. An omitted `.arg_names`
  registers `"arg0"`, `"arg1"`, ... instead, and the resolved entry's
  `argName(index)` applies that fallback.
- An instance method takes `*T` or `*const T` as its first parameter. `*const T`
  sets `is_const`, and the self parameter is excluded from the engine argument
  list. A static method takes only engine arguments, so a static entry that
  still receives a self pointer is a compile error. Registration derives
  `METHOD_FLAG_STATIC` from the marker and `METHOD_FLAG_CONST` from the self
  parameter.
- Functions must be non-generic and non-varargs. Return and argument types come
  from the Zig signature; the marker only supplies the names Godot needs for
  GDScript keyword arguments.
- Every engine parameter and non-void return must support both the Variant and
  ptrcall paths through the internal conversion layer, and the compile error
  names the method and argument. Custom types with a `Conversion` marker are
  accepted wherever both paths are supported, but an argument must also be
  borrow-like.
- Method arguments are **call-scoped borrowed** and the declaration gate enforces
  it. A directly supported type is accepted: it crosses as the engine value, and
  the adapter releases its Variant-path copy after the call. A custom converter is
  accepted only when its decoded value declares no `deinit` and its engine
  representation owns no storage - a canonical scalar, a plain builtin, or a
  non-`RefCounted` object pointer. Owning forms are compile errors as arguments:
  `Ref(T)`, typed container wrappers, and converters whose engine representation
  is a managed/heap/packed builtin or a `RefCounted` object pointer. Declare the
  borrowed direct type instead and wrap explicitly inside the method; owning
  wrappers stay valid for results, properties, and generated engine-method
  results.
- `findMethods(T)` returns one resolved entry type per method: engine name,
  implementation function value and `Fn` type, `is_static`, `is_const`, engine
  `arg_count`, the explicit `arg_names`, and `argName(index)`. Duplicate engine
  names are compile errors. `findMethods` is the declaration surface; the
  registration stage consumes the entries and adds the two callbacks.
- Vararg methods and default arguments are not supported. Zig function types do
  not carry parameter names, and comptime `Variant` construction is limited to
  scalars and nil, so default arguments would need a deferred registration-time
  Variant table. Neither is worth blocking on.

Registration writes one `GDExtensionClassMethodInfo` per resolved entry through
`classdb_register_extension_class_method`:

- `method_userdata` is null: the adapters are non-capturing and the class
  instance arrives as `p_instance`.
- `name` is the engine name; `method_flags` is the normal-method flag plus
  `METHOD_FLAG_CONST` when the self parameter is `*const T` and
  `METHOD_FLAG_STATIC` when the marker says static.
- Each argument's `PropertyInfo` carries its registered name (`argName`), the
  declared type's engine Variant type and engine class name from the internal
  conversion layer, an empty hint string, and `.none` metadata. A `Variant`
  argument or result registers as untyped `.nil` with
  `PROPERTY_USAGE_NIL_IS_VARIANT` (131072); without that usage bit GDScript reads
  the slot as `void` instead of `Variant`.
- Return metadata exists only when the method returns a non-void value and is
  `.none`; `default_argument_count` is zero and `default_arguments` is null (see
  the vararg/default-argument rule above).
- The engine copies the method name and every metadata table during the call, so
  registration builds stack temporaries and allocates nothing.

Both call paths are mandatory and implemented together:

1. `call_func` is the Variant path used by `Object.call`/`callv`, `Callable`,
   signals, and dynamic GDScript dispatch. It checks the argument count
   (`GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS`/`..._TOO_MANY_ARGUMENTS` with
   `expected` set to the method's engine argument count), then the instance (an
   instance method with a null `p_instance` reports
   `GDEXTENSION_CALL_ERROR_INSTANCE_IS_NULL`), then decodes one Variant per
   argument. A null argument pointer or a Variant that does not hold the declared
   representation reports `GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT` with the
   argument index and the expected Variant type. The return slot is set to
   `Variant.nil` before dispatch and receives the encoded result on success.
   Arguments decoded before a later mismatch are still released.
2. `ptrcall_func` is the path a validated GDScript call uses. It decodes one raw
   slot per argument and writes the return slot; it reports no errors because the
   engine only compiles the validated call after matching the signature. The
   engine has no ptrcall-to-call fallback, so both adapters are always
   registered. `validated_call_func` is deliberately not implemented: the engine
   falls back to `ptrcall_func`, which is the path a validated call takes.

The adapters release every call-scoped decoded argument through the conversion
layer after the user function returns, on the early-error paths too. Method
arguments are therefore **borrowed for the call**: an implementation must not
store, deinit, or transfer a decoded argument. The declaration gate already
rejects the owning forms (see the argument rule in D4), so the release is a no-op
for ordinary argument types and only releases adapter-managed copies of direct
managed builtins and `Variant`. When the implementation needs to keep something,
take the borrowed direct argument and own it explicitly:

```zig
// Field: resource: Property(godot.ownership.Ref(Resource), .{ ... })
pub fn track(self: *@This(), resource: ?*godot.classes.core.Resource) void {
    self.resource.value = godot.ownership.Ref(godot.classes.core.Resource).init(resource);
}
```

Results are outgoing engine values, like virtual returns:

- A raw `?*T` result is borrowed: the engine slot takes its own reference to a
  `RefCounted` object (or its own copy of a builtin), so return an object you
  keep alive elsewhere with `.get()`. `Ref` is not the return form for a borrowed
  object.
- An owned `RefCounted` result is declared as `godot.ownership.Ref(T)`: the
  adapter encodes the object into the engine slot and then releases the returned
  wrapper, so the engine keeps the slot's reference and the handle does not leak.
- A managed builtin result is moved into the ptrcall slot and released after the
  Variant encode.

Owning wrappers are valid in the result position (and as `Property` storage and
generated engine-method results); only the argument position is borrow-only.

The ownership model for these call-scoped arguments and outgoing results is
stated once in [ownership.md](ownership.md#the-model); the conversion layer's
encoding direction is in [conversion.md](conversion.md#ownership-direction).

Static methods need `METHOD_FLAG_STATIC` because the engine nulls the instance
handle for static calls and dereferences it otherwise. The marker records
staticness explicitly and signature validation checks the self parameter agrees;
registration derives the engine flag from the marker.

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
  `NotificationCallback`, `get_virtual_func`, and any `Methods` entry not marked
  `.is_static = true`.
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
godot.annotations.Methods(.{ ... })       // one class-level method container
godot.annotations.Method(impl, options)   // one method declaration
godot.annotations.findMethods(T)          // method discovery, one entry type per method
godot.registration.classdb.postRegistrationCallback(T)
godot.registration.PostRegistrationCallback
godot.registration.ClassOptions.is_virtual

// planned
godot.registration.ClassOptions.is_abstract      // no-instance class mode (D6)
godot.annotations.Constant(value, opts)  // optional override inside Constants
```

New files:

| File | Owns | State |
|---|---|---|
| `src/godot/annotations/signal.zig` | `Signal` marker, argument validation, discovery, typed `emit` | implemented |
| `src/godot/annotations/constants.zig` | `Constants` marker, constant/enum/bitfield discovery, and enum/bitfield hint metadata | implemented |
| `src/godot/annotations/methods.zig` | `Method`/`Methods` markers, discovery, signature validation, resolved entry types | implemented |
| `src/godot/registration/methods.zig` | ClassDB method metadata and the `call_func`/`ptrcall_func` adapters | implemented |
| `src/godot/registration/classdb.zig` | family gate and order (constants, signals, methods), registration calls, copied argument metadata | implemented |
| `src/godot/conversion.zig` (internal) | declared-type support/metadata queries, Variant-path conversion, converter bridge, decoded-argument release, and the method-argument ownership gate; direct ptrcall slots via `ptrcall.zig` | implemented |

The metadata queries these calls need come from the internal conversion layer:
it derives a declared type's engine Variant type and engine class name (a
`Conversion` marker's engine representation is followed), and it is the only
place that decides value conversion. Registration passes the declarations in and
receives metadata; it does not compose a class-name lookup at the call site.

Discovery follows the established shape: a `find*` function that scans the
class's type declarations, filters on `marker.Kind` first, re-derives the family
type and validates its shape, and returns a comptime slice in declaration order.
Every declaration marker uses that identity: `signal`, `methods`, `constants`,
`property_groups`, and `override` for class-level declarations, plus the
callback kinds; `Conversion` is the type-attached `conversion` marker. `Init` is
not a marker. Identity and the 13-kind table are in
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
re-exported by the registration module. One callback body composes the families
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

1. integer constants (`..._integer_constant`)
2. signals (`..._signal`)
3. methods (`..._method`)

Constants, signals, and methods are independent registrations today; the order
is the family list in `registration/classdb.zig` and a future static-property
surface must run after methods. Argument names, Variant types, and engine class
names are expanded at comptime through the internal conversion layer; the engine
copies the resulting metadata, so no per-value conversion happens during
registration.

Groups and dynamic properties are part of `ClassCreationInfo6` and are not
registered here. `classdb_unregister_extension_class` drops the class and its
metadata, so deinitialization needs no per-surface calls.

No allocation is added: the tables are comptime values, and the engine copies
each `StringName`/`PropertyInfo`/`String` during the registration call, so
nothing class-level outlives it. The property list is the exception: the engine
holds its array until `free_property_list_func`, so it stays a process-lifetime
per-class static.

## Verification

Discovery, metadata expansion, the call adapters, and the conversion contract are
covered by compile-only checks and unit tests under `zig build test-godot`
(`tests/conversion.zig` pins declared-type support/metadata, the Variant path,
the decoded-argument release helper, and the method-argument ownership gate;
`tests/ptrcall.zig` pins the direct slot
rules; the annotation tests pin discovery and declaration errors, including
method flattening, argument names, signature shape, and borrow-like arguments;
`tests/registration` pins
method flags, metadata/adapter analysis, the error reports, and the release
counts for scalar and converter result signatures). The optional
[`test-godot-live`](build.md#live-godot-tests) step verifies registration
metadata and calls for the live fixture classes in a headless Godot process;
other class-level surfaces and editor-only behavior remain compile-only or
manual.

## Non-goals

- no static property backend for instanced classes (D1)
- no generator or bindings changes (D7)
- no vararg methods or default arguments (D4)
- no `validated_call_func` registration; the engine falls back to `ptrcall_func`
- no `classdb_register_extension_class_virtual_method` (D6)
- no extension-to-extension inheritance, which Godot 4 does not support
- no automatic registration of a class's Zig methods, enums, or signals:
  discovery is declaration-marker driven, never inferred from the class body
