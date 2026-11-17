# Reflection

`reflect/` is hand-written support code. It does not generate declarations and it
does not register classes.

## Files

```text
reflect/
  reflect.zig       public aggregator
  meta.zig          type predicates and ValueType
  functions.zig     function-shape helpers
  inheritance.zig   Extends-chain traversal and engine-class detection
  defaults.zig      initFieldsDefault
```

## Rules

- `reflect` contains the hand-written reflection helpers.
- `initFieldsDefault` initializes ordinary Zig field defaults after
  `allocator.create`. It is generic and not annotation-specific.
- `inheritsFrom` follows `Extends` and accepts struct, opaque, or extension
  classes. It is the same hierarchy rule used by `upcast` and `downcast`.
- `isLikelyNamespace` detects a zero-field non-tuple struct. It is a best-effort
  shape check and deliberately does not inspect `Extends`; callers that care
  about extension classes must add that guard.
- `isOptionalPointer` recognizes `?*T` and `?*const T`.
- `isRefCounted` follows the `Extends` chain to `RefCounted`.
- `isRefCountedPointer` applies `isRefCounted` to the pointee, so `?*Resource`
  and `*Resource` are recognized.
- `className` returns `GodotClassName` when present, otherwise the exact short
  Zig type name. Registration and instance attachment use the same helper.
- Reflection never owns instances and never calls registration callbacks.

Annotations are separate. Use `annotations.initAnnotFieldsDefault` for
annotation fields and `registration` for lifecycle wiring.
