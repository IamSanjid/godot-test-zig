//! Declared Zig value <-> engine value conversion. Properties, virtuals, and
//! signals use it; methods and containers will. See docs/conversion.md.

pub const Path = enum { variant, ptr };

pub const Support = struct {
    /// A Variant representation exists. `variantType` may still be null for
    /// `Variant` itself, which stores transparently.
    variant: bool,
    /// A ptrcall representation exists.
    ptr: bool,
};

/// Conversion support for `T`, following one `Conversion` marker.
pub fn support(comptime T: type) Support {
    return SupportCache(T).value;
}

/// The engine type `T` converts to: `T` for a directly supported type, the
/// marker's `Engine` for a converter, and null when neither applies.
pub fn engineType(comptime T: type) ?type {
    return EngineTypeCache(T).value;
}

/// The Variant type of `T`'s engine representation. Null for `Variant` itself
/// (transparent storage) and for types with no Variant representation.
pub fn variantType(comptime T: type) ?interface.VariantType {
    return VariantTypeCache(T).value;
}

/// The engine class name of `T`'s engine representation, or empty when it is
/// not an object pointer. Follows a converter's engine type.
pub fn engineClassName(comptime T: type) [:0]const u8 {
    const Engine = engineType(T) orelse return "";
    return reflect.classNameOf(Engine);
}

fn SupportCache(comptime T: type) type {
    return struct {
        const value: Support = computeSupport(T);
    };
}

fn computeSupport(comptime T: type) Support {
    const info = comptime markerInfo(T) orelse return directSupport(T);
    return directSupport(info.engine);
}

fn EngineTypeCache(comptime T: type) type {
    return struct {
        const value = computeEngineType(T);
    };
}

fn computeEngineType(comptime T: type) ?type {
    if (comptime markerInfo(T)) |info| return info.engine;
    const direct = comptime directSupport(T);
    return if (direct.variant or direct.ptr) T else null;
}

fn VariantTypeCache(comptime T: type) type {
    return struct {
        const value = computeVariantType(T);
    };
}

fn computeVariantType(comptime T: type) ?interface.VariantType {
    const Engine = engineType(T) orelse return null;
    return builtins.Variant.typeFor(Engine);
}

/// Compile-checks that `T` has `path` support, with an error that names
/// `context`. No conversion is a context error; a malformed marker points at
/// the marker field instead.
pub fn checkSupported(comptime T: type, comptime path: Path, comptime context: []const u8) void {
    const available = comptime support(T);
    const ok = comptime switch (path) {
        .variant => available.variant,
        .ptr => available.ptr,
    };
    if (comptime !ok) @compileError(noConversionMessage(T, path, context));
}

/// `checkSupported` for both the Variant and ptrcall paths.
pub fn checkBoth(comptime T: type, comptime context: []const u8) void {
    checkSupported(T, .variant, context);
    checkSupported(T, .ptr, context);
}

/// Decodes `T` from a Variant, or null when the Variant does not hold `T`'s
/// engine representation. Ownership follows `Variant.asDeclared`; conversion
/// goes through the marker's `fromEngine`.
pub fn decodeVariant(comptime T: type, value: *const builtins.Variant) ?T {
    checkSupported(T, .variant, "decodeVariant");
    if (comptime markerInfo(T)) |info| {
        const engine_value = value.asDeclared(info.engine) orelse return null;
        defer deinitEngine(info.engine, engine_value);
        return @field(info.marker, "fromEngine")(engine_value);
    }
    return value.asDeclared(T);
}

/// Decodes `T` from one ptrcall argument slot. `RefCounted` pointers use
/// `ref_get_object`; extension-class pointers resolve their Zig instance;
/// every other type reads its ABI representation.
pub fn decodePtr(comptime T: type, raw: ?*const anyopaque) T {
    checkSupported(T, .ptr, "decodePtr");
    if (comptime markerInfo(T)) |info| {
        return @field(info.marker, "fromEngine")(decodeDirectPtr(info.engine, raw));
    }
    return decodeDirectPtr(T, raw);
}

/// Encodes `value` into a Variant with the copy/ownership behavior of
/// `Variant.initDeclared`. `value` is the declared type `T` or a form
/// `Variant.initDeclared` accepts for it (a coercible literal, a pointer to an
/// extending engine/extension class); a converter type requires a `T` value.
/// Conversion goes through the marker's `toEngine` first.
pub fn encodeVariant(comptime T: type, value: anytype, out: *builtins.Variant) void {
    checkSupported(T, .variant, "encodeVariant");
    if (comptime markerInfo(T)) |info| {
        const engine_value = @field(info.marker, "toEngine")(value);
        defer deinitEngine(info.engine, engine_value);
        out.* = builtins.Variant.initDeclared(info.engine, engine_value);
        return;
    }
    out.* = builtins.Variant.initDeclared(T, value);
}

/// Encodes `T` into one ptrcall return slot. `RefCounted` pointers use
/// `ref_set_object`; extension-class pointers write their engine base;
/// every other type writes its ABI representation.
pub fn encodePtr(comptime T: type, value: T, raw: ?*anyopaque) void {
    checkSupported(T, .ptr, "encodePtr");
    if (comptime markerInfo(T)) |info| {
        encodeDirectPtr(info.engine, @field(info.marker, "toEngine")(value), raw);
        return;
    }
    encodeDirectPtr(T, value, raw);
}

const MarkerInfo = struct {
    marker: type,
    engine: type,
};

fn MarkerInfoCache(comptime T: type) type {
    return struct {
        const value = computeMarkerInfo(T);
    };
}

fn markerInfo(comptime T: type) ?MarkerInfo {
    return MarkerInfoCache(T).value;
}

fn computeMarkerInfo(comptime T: type) ?MarkerInfo {
    // Directly supported types are converted as themselves, so their
    // declarations are never scanned. This also avoids forcing unrelated
    // declaration values (for example generated generic helpers that raise
    // conditional compile errors on some instantiations).
    const direct = comptime directSupport(T);
    if (comptime direct.variant or direct.ptr) return null;

    const Marker = comptime conversion_marker.find(T) orelse return null;
    validateMarker(T, Marker);
    return .{
        .marker = Marker,
        .engine = comptime conversion_marker.MarkerEngine(Marker),
    };
}

fn directSupport(comptime T: type) Support {
    if (comptime T == void) return .{ .variant = false, .ptr = false };

    const variant = comptime T == builtins.Variant or builtins.Variant.typeFor(T) != null;
    const ptr = comptime variant or isSingleItemPointer(T);
    return .{ .variant = variant, .ptr = ptr };
}

fn isSingleItemPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |info| info.size == .one,
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => |child| child.size == .one,
            else => false,
        },
        else => false,
    };
}

/// Releases an owning engine intermediate after a converter has borrowed it.
/// Values without a `deinit` declaration (scalars, object pointers) are no-ops.
fn deinitEngine(comptime E: type, value: E) void {
    switch (@typeInfo(E)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => {
            if (comptime @hasDecl(E, "deinit")) {
                var copy = value;
                copy.deinit();
            }
        },
        else => {},
    }
}

fn decodeDirectPtr(comptime T: type, raw: ?*const anyopaque) T {
    if (comptime reflect.objectTarget(T)) |target| {
        if (comptime target.kind == .extension) return decodeExtensionPtr(T, target, raw);
    }
    if (comptime reflect.isRefCountedPointer(T)) return decodeRefCountedPtr(T, raw);
    return abi.readArgument(T, raw);
}

fn encodeDirectPtr(comptime T: type, value: T, raw: ?*anyopaque) void {
    if (comptime reflect.objectTarget(T)) |target| {
        if (comptime target.kind == .extension) return encodeExtensionPtr(T, target, value, raw);
    }
    if (comptime reflect.isRefCountedPointer(T)) return encodeRefCountedPtr(T, value, raw);
    abi.writeReturn(T, raw, value);
}

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

fn validateMarker(comptime T: type, comptime Marker: type) void {
    const Engine = comptime conversion_marker.MarkerEngine(Marker);
    inline for (.{ "toEngine", "fromEngine" }) |field_name| {
        if (comptime !@hasDecl(Marker, field_name)) @compileError(std.fmt.comptimePrint(
            "Type '{s}' has an invalid Conversion marker '{s}': missing '.{s}'.",
            .{ @typeName(T), @typeName(Marker), field_name },
        ));
    }

    const EngineSupport = directSupport(Engine);
    if (comptime !EngineSupport.variant and !EngineSupport.ptr) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': '.Engine' must have a Variant or " ++
            "ptrcall representation; found '{s}'.",
        .{ @typeName(T), @typeName(Marker), @typeName(Engine) },
    ));
    if (comptime Engine == builtins.Variant) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': '.Engine' cannot be Variant itself; " ++
            "Variant has transparent storage, so choose a concrete representation type.",
        .{ @typeName(T), @typeName(Marker) },
    ));

    validateConverterFn(T, Marker, "toEngine", @TypeOf(@field(Marker, "toEngine")), T, Engine);
    validateConverterFn(T, Marker, "fromEngine", @TypeOf(@field(Marker, "fromEngine")), Engine, T);
}

fn validateConverterFn(
    comptime T: type,
    comptime Marker: type,
    comptime field_name: []const u8,
    comptime Fn: type,
    comptime Param: type,
    comptime Return: type,
) void {
    const info = switch (@typeInfo(Fn)) {
        .@"fn" => |fn_info| fn_info,
        else => @compileError(converterMessage(T, Marker, field_name, Param, Return, Fn)),
    };
    if (info.is_generic or info.attrs.varargs or info.param_types.len != 1) {
        @compileError(converterMessage(T, Marker, field_name, Param, Return, Fn));
    }
    if (info.param_types[0] != Param) {
        @compileError(converterMessage(T, Marker, field_name, Param, Return, Fn));
    }
    if ((info.return_type orelse void) != Return) {
        @compileError(converterMessage(T, Marker, field_name, Param, Return, Fn));
    }
}

fn pathName(comptime path: Path) []const u8 {
    return switch (path) {
        .variant => "variant",
        .ptr => "ptrcall",
    };
}

fn noConversionMessage(
    comptime T: type,
    comptime path: Path,
    comptime context: []const u8,
) []const u8 {
    return std.fmt.comptimePrint(
        "{s}: type '{s}' has no {s} conversion; add a Conversion marker with .engine = <supported type>",
        .{ context, @typeName(T), pathName(path) },
    );
}

fn converterMessage(
    comptime T: type,
    comptime Marker: type,
    comptime field_name: []const u8,
    comptime Param: type,
    comptime Return: type,
    comptime Fn: type,
) []const u8 {
    return std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': '.{s}' must be a non-generic, " ++
            "non-varargs function taking one '{s}' and returning '{s}'; found '{s}'.",
        .{ @typeName(T), @typeName(Marker), field_name, @typeName(Param), @typeName(Return), @typeName(Fn) },
    );
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const abi = @import("abi.zig");
const builtins = @import("builtins/builtins.zig");
const conversion_marker = @import("annotations/conversion.zig");
const reflect = @import("reflect/reflect.zig");
const runtime = @import("runtime.zig");
