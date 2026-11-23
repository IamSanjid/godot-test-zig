# Reflection

`reflect/` is hand-written support code. It does not generate declarations and it
does not register classes.

## Files

```text
reflect/
  reflect.zig       public aggregator
  hierarchy.zig     Extends traversal (inheritsFrom, extendsType)
  meta.zig          type predicates and UnwrappedType
  functions.zig     function-shape helpers
  base.zig          annotation-free Base marker discovery
  objects.zig       class kinds, object pointers, RefCounted classification
  extension.zig     extension-class engine-base resolution and marker policy
  defaults.zig      initFieldsDefault
```

## Rules

- `reflect` contains the hand-written reflection helpers.
- `initFieldsDefault` initializes ordinary Zig field defaults after
  `allocator.create`. It is generic and not annotation-specific.
- `hierarchy.zig` is the pure `Extends` primitive: `inheritsFrom` follows the
  chain and `extendsType` reports a declaration's direct parent. It carries no
  generated-class or object policy; `objects.zig` and `extension.zig` layer that
  on top.
- `inheritsFrom` follows `Extends` for engine and extension classes. Generated
  `upcast` uses the same rule; generated `downcast` asks the engine at runtime
  (`isClass`) instead.
- `objects.zig` classifies engine object classes (opaque generated classes such
  as `classes.core.Node`) and extension classes (Zig structs whose `Extends`
  chain reaches an engine object class); `isClassType` is either. Zero-field
  extension declarations are valid extension classes; use `isLikelyNamespace`
  with an `Extends` check to distinguish namespaces.
- `isNodeClass` and `isResourceClass` take an engine or extension class type and
  report whether its `Extends` chain reaches `Node` or `Resource`; object
  pointers and non-class types return false.
- `objectTarget` classifies `*C`, `*const C`, `?*C` and `?*const C` as engine or
  extension object pointers. Class values, arrays, many-pointers, and slices are
  not object pointers.
- `isRefCounted` follows the `Extends` chain to `RefCounted`.
  `isRefCountedPointer` resolves the class behind `objectTarget`, so it accepts
  only a single-item pointer/optional pointer to a class type descending from
  `RefCounted`. Arrays, many-pointers, slices, and class values are rejected.
- `isOptionalPointer` recognizes only `?*T` and `?*const T`; optional
  many-pointers and optional slices are not pointer optionals.
- `base.zig` discovers Base marker fields structurally (a normal struct declaring
  `BaseFor` plus `get`/`set` accessors), so `Variant` and registration can use
  them without importing annotations.
- `extension.zig` resolves an extension class to the ultimate engine object it
  wraps (`EngineBaseType`) and walks the runtime marker chain
  (`engineBasePointer`). Every extension level needs one
  `Base(<direct parent>)` marker field; the terminal engine class needs none.
  Missing or mismatched markers are compile errors.
- `className` returns `GodotClassName` when present, otherwise the exact short
  Zig type name. Registration and instance attachment use the same helper.
- `classNameOf` returns the engine class name of an object pointer type
  (`*C`, `?*C`, `*const C`, `?*const C`) and an empty string for anything else.
  The property backend uses it for object-typed properties and as the
  registration fallback; enum/bitfield hints carry no class name unless the type
  is declared in the class's `Constants`, which supplies its own
  `<Class>.<Name>` qualifier. It composes `objectClassOf` and `className`.
- Reflection never owns instances and never calls registration callbacks.

Annotations are separate. Use `annotations.initAnnotFieldsDefault` for
annotation fields and `registration` for lifecycle wiring.
