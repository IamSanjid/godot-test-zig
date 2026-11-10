Foo.zig:
```zig
pub const Extends = godot.Sprit2D;

// will be converted into call-convention(.c) if it is not already,
// for these type of "event" functions you should convert it to callconv(.c)
pub fn _ready() callconv(.c) void {
    
}

// will be converted into snake case while registering the method to the engine.
// so `_physics_process`, the bindgen will parse some sort of metadata so the
// argument types match and will report during compilation on mismatches.
pub fn _physicsProcess(delta: f32) callconv(.c) void {
    
}
```

`scanForClassesToRegister` during build should find all the .zig files with some excluding rules, if a .zig file contains at least one line `pub const Extends = <BaseT>;` and a field with type `*<BaseT>` it will be marked as a module to look for "classes" to register.


the `src/godot/bindings` for internal classes and their methods + op will try to follow this format:
```zig
    pub fn getSupport(dispatcher: anytype, self: *const Aabb, p_direction: Vector3) Vector3 {
        var args: [1]c.GDExtensionConstTypePtr = undefined;
        args[0] = @ptrCast(&p_direction);
        var result: Vector3 = .zero;
        if (getSupport_ptr == null) {
            @branchHint(.cold);
            getSupport_ptr = dispatcher.dispatch(.variant_get_ptr_builtin_method, .{ @backingInt(Variant.Tag.forType(Aabb)), @ptrCast(&StringName.fromComptimeLatin1("get_support")), 2923479887 }).?;
        }
        getSupport_ptr.?(@ptrCast(@constCast(self)), @ptrCast(&args), @ptrCast(&result), args.len);
        return result;
    }
    var getSupport_ptr: c.GDExtensionPtrBuiltInMethod = null;
```
Also will expose a comptime fn to check the layout(field offsets + size).

"bindings" are a completely different module, it doesn't depend on anything else.
we will write codegen which is similar to "bindings" mainly which will wrap the bindings into our "auto" godot convention, extends, auto casting to Variant etc..
