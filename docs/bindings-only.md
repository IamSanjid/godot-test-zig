# Bindings only

The raw bindings layer is usable without `godot.zig`, `runtime.zig`, the codegen
tree, annotations, or registration. This is the path for a project that wants
its own lifecycle and dispatch policy.

## What to keep

- `gd_interface/` and the generator (`generator/`, `build/generator.zig`) for
  regenerating ABI wrappers.
- `src/godot/bindings/bindings.zig` and the generated files beside it.
- `build.zig.zon` dependencies used by the generator, including
  `translate_c` and `casez` (the naming module is compiled into the generator).
- The `bindgen` wiring in `build.zig`.

You can remove the codegen output, `godot.zig`, `runtime.zig`, `abi.zig`,
`ptrcall.zig`, `conversion.zig`, `ownership.zig`, `collections.zig`, `heap.zig`,
`reflect/`, `annotations/`, `registration/`, `src/example*`, and the
class-file scanner/`zlob` dependency if you do not use them. Regenerate with
`zig build bindgen`, not `zig build gen`.

## Expose the module

The default `build.zig` has the raw `bindings` module import for the entrypoint
commented out. Add or uncomment it, and replace the helpful `godot` module
import in your entrypoint module with the raw one:

```zig
const bindings_module = b.createModule(.{
    .root_source_file = b.path("src/my_extension.zig"),
    .imports = &.{
        .{ .name = "bindings", .module = bindings },
    },
    .target = target,
    .optimize = optimize,
});
```

Then import it directly:

```zig
const bindings = @import("bindings");
const interface = bindings.interface;
```

The bindings module needs only `std` and the translated `godot_interface`
module. It does not import the runtime.

## Minimal entry point

```zig
const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

var dispatcher: bindings.Dispatcher(&.{}) = undefined;

fn initialize(_: ?*anyopaque, _: interface.InitializationLevel) callconv(.c) void {}

fn deinitialize(_: ?*anyopaque, _: interface.InitializationLevel) callconv(.c) void {}

export fn my_game_init(
    get_proc_address: interface.InterfaceGetProcAddress,
    library: interface.ClassLibraryPtr,
    initialization: *interface.Initialization,
) callconv(.c) bool {
    dispatcher = .init(get_proc_address.?, library, null) catch |err| {
        std.log.err("dispatcher initialization failed: {t}", .{err});
        return false;
    };

    initialization.* = .{
        .minimum_initialization_level = .scene,
        .userdata = null,
        .initialize = &initialize,
        .deinitialize = &deinitialize,
    };
    return true;
}
```

Every generated raw wrapper takes a `dispatcher` parameter and calls
`dispatcher.dispatch(...)`. Pass `&dispatcher` to those functions. This layer
does not provide `godot.engine_allocator`, class registration, annotations, or
the hand-written `Variant` layer; those are all part of the optional runtime
layer. It does include the raw binding Variant and its
`bindings.builtins.Variant.borrow` helper, which is separate from the runtime
`Variant.Borrowed` view.

## Caveats

- `Dispatcher(&.{})` resolves every proc in the bundled interface JSON during
  initialization. It fails on an engine missing any proc, so regenerate from
  the version you actually target.
- Generated wrappers cache proc and method pointers lazily. Initialize and warm
  the paths you use before calling from multiple threads.
- The bindings module still needs `translate_c`, the GDExtension header, and the
  generated interface module at build time.
- Keep a hand-written `bindings.zig` if the layer root changes; it is the module
  entry point, not generated output.
- Method results of `RefCounted` classes carry an owning reference but are raw
  pointers here; there is no `godot.ownership.Ref` or `Owned` in this mode, and
  `construct()`/`constructLegacy()` return the raw creation pointer. Manage
  results with the generated `RefCounted.reference`/`unreference` and
  `Object.destroy`, or use the runtime layer, which wraps results and
  constructors in the typed handles ([ownership.md](ownership.md)).
