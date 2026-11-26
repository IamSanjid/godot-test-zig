//! Direct ptrcall slot rules. `RefCounted` slots store a `GDExtensionRefPtr`:
//! reads are borrowed for the call, writes need engine-owned reference storage.
//! Extension-class pointers resolve their Zig instance; every other type uses
//! its canonical ABI representation (see `abi.zig`). No Variant/property logic.

/// Decodes `T` from one ptrcall argument slot. `RefCounted` pointers read the
/// borrowed object reference; extension-class pointers resolve their Zig
/// instance; every other type reads its ABI representation.
pub fn decodeDirectPtr(comptime T: type, raw: ?*const anyopaque) T {
    if (comptime reflect.objectTarget(T)) |target| {
        if (comptime target.kind == .extension) return decodeExtensionPtr(T, target, raw);
    }
    if (comptime reflect.isRefCountedPointer(T)) return decodeRefCountedPtr(T, raw);
    return abi.readArgument(T, raw);
}

/// Encodes `T` into one ptrcall return slot. `RefCounted` pointers add the
/// reference the engine-owned slot keeps; extension-class pointers write their
/// engine base; every other type writes its ABI representation.
pub fn encodeDirectPtr(comptime T: type, value: T, raw: ?*anyopaque) void {
    if (comptime reflect.objectTarget(T)) |target| {
        if (comptime target.kind == .extension) return encodeExtensionPtr(T, target, value, raw);
    }
    if (comptime reflect.isRefCountedPointer(T)) return encodeRefCountedPtr(T, value, raw);
    abi.writeReturn(T, raw, value);
}

/// Reads a `RefCounted` object pointer from a ptrcall slot. The GDExtension ABI
/// stores such slots as `GDExtensionRefPtr` (one pointer), and the engine owns
/// that reference for the duration of the call, so the returned object pointer
/// is borrowed.
fn decodeRefCountedPtr(comptime T: type, raw: ?*const anyopaque) T {
    const ref: interface.ConstRefPtr = @ptrCast(@alignCast(raw));
    const object = runtime.dispatch(.ref_get_object, .{ref});

    if (comptime reflect.isOptionalPointer(T)) {
        return if (object) |value| @ptrCast(value) else null;
    }
    return @ptrCast(object orelse @panic(
        "Godot passed a null RefCounted object for a non-optional value",
    ));
}

/// Writes a `RefCounted` object into an engine-owned reference slot, adding the
/// reference that slot owns. Only valid for slots the ABI declares as RefCounted
/// storage; never write a raw object pointer into one.
fn encodeRefCountedPtr(comptime T: type, value: T, raw: ?*anyopaque) void {
    const object: interface.ObjectPtr = if (comptime reflect.isOptionalPointer(T))
        if (value) |item| @ptrCast(item) else null
    else
        @ptrCast(value);

    runtime.dispatch(.ref_set_object, .{
        @as(interface.RefPtr, @ptrCast(@alignCast(raw))),
        object,
    });
}

fn decodeExtensionPtr(
    comptime T: type,
    comptime target: reflect.ObjectTarget,
    raw: ?*const anyopaque,
) T {
    const Class = target.class;
    const Base = reflect.EngineBaseType(Class);
    const maybe_base: ?*Base = if (comptime reflect.isRefCounted(Class)) blk: {
        const ref: interface.ConstRefPtr = @ptrCast(@alignCast(raw));
        const object = runtime.dispatch(.ref_get_object, .{ref});
        break :blk if (object) |value| @ptrCast(value) else null;
    } else abi.readArgument(?*Base, raw);

    const base = maybe_base orelse {
        if (comptime target.optional) return null;
        @panic("Godot passed a null extension object for a non-optional value");
    };
    const instance = base.asInstance(Class) orelse {
        if (comptime target.optional) return null;
        @panic("Godot passed an engine object without the extension instance");
    };
    return @ptrCast(instance);
}

fn encodeExtensionPtr(
    comptime T: type,
    comptime target: reflect.ObjectTarget,
    value: T,
    raw: ?*anyopaque,
) void {
    const Class = target.class;
    const Base = reflect.EngineBaseType(Class);

    if (comptime reflect.isRefCounted(Class)) {
        const object: interface.ObjectPtr = if (comptime target.optional)
            if (value) |item| @ptrCast(reflect.engineBasePointer(Class, item)) else null
        else
            @ptrCast(reflect.engineBasePointer(Class, value));

        runtime.dispatch(.ref_set_object, .{
            @as(interface.RefPtr, @ptrCast(@alignCast(raw))),
            object,
        });
        return;
    }

    if (comptime target.optional) {
        const maybe_base: ?*Base = if (value) |item| reflect.engineBasePointer(Class, item) else null;
        abi.writeReturn(?*Base, raw, maybe_base);
        return;
    }
    abi.writeReturn(*Base, raw, reflect.engineBasePointer(Class, value));
}

const bindings = @import("bindings");
const interface = bindings.interface;

const abi = @import("abi.zig");
const reflect = @import("reflect/reflect.zig");
const runtime = @import("runtime.zig");
