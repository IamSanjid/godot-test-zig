//! Declared Zig value <-> engine value conversion, used by properties, signals,
//! virtuals, methods, and collections. Not public API: the Variant path and
//! declared-type mapping live here, direct ptrcall slot rules live in
//! `ptrcall.zig`. See docs/conversion.md.

pub const Path = enum { variant, ptrcall };

pub const Support = struct {
    /// A Variant representation exists. `variantType` may still be null for
    /// `Variant` itself, which stores transparently.
    variant: bool,
    /// A ptrcall representation exists.
    ptrcall: bool,
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
    return if (direct.variant or direct.ptrcall) T else null;
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
        .ptrcall => available.ptrcall,
    };
    if (comptime !ok) @compileError(noConversionMessage(T, path, context));
}

/// `checkSupported` for both the Variant and ptrcall paths.
pub fn checkBoth(comptime T: type, comptime context: []const u8) void {
    checkSupported(T, .variant, context);
    checkSupported(T, .ptrcall, context);
}

/// Decodes `T` from a Variant, or null when the Variant does not hold `T`'s
/// engine representation. Ownership follows `Variant.asDeclared`; conversion
/// goes through the marker's `fromEngine`.
pub fn decodeVariant(comptime T: type, value: *const builtins.Variant) ?T {
    checkSupported(T, .variant, "decodeVariant");
    if (comptime markerInfo(T)) |info| {
        const engine_value = value.asDeclared(info.engine) orelse return null;
        defer deinitEngine(info.engine, engine_value);
        return info.marker.fromEngine(engine_value);
    }
    return value.asDeclared(T);
}

/// Decodes `T` from one ptrcall argument slot, or through the marker's
/// `fromEngine` first. Direct types delegate to `ptrcall.decodeDirectPtr`.
pub fn decodePtrcallSlot(comptime T: type, raw: ?*const anyopaque) T {
    checkSupported(T, .ptrcall, "decodePtrcallSlot");
    if (comptime markerInfo(T)) |info| {
        return info.marker.fromEngine(ptrcall.decodeDirectPtr(info.engine, raw));
    }
    return ptrcall.decodeDirectPtr(T, raw);
}

/// Releases one decoded method argument after the user function returns.
/// Variant-path direct values own their decode; ptrcall direct values are
/// borrowed. Converter results own on both paths.
///
/// Call it with the path the argument was decoded on. Method arguments are
/// call-scoped borrowed (see `checkMethodArgument`): the method adapter releases
/// the decode after the user function returns, and user code must not `deinit` or
/// store an argument. Types without a `deinit` declaration (scalars, plain
/// builtins, object pointers) are no-ops.
pub fn deinitDecodedArgument(comptime T: type, comptime path: Path, value: *T) void {
    checkSupported(T, path, "deinitDecodedArgument");
    const owns = comptime switch (path) {
        .variant => true,
        .ptrcall => markerInfo(T) != null,
    };
    if (comptime owns and hasDeinit(T)) value.deinit();
}

/// True when a method argument of declared type `T` is borrow-like: direct types
/// (the adapter releases their Variant-path decode) or converters whose decoded
/// value owns nothing and whose engine representation owns no storage.
pub fn methodArgumentIsBorrowed(comptime T: type) bool {
    const info = comptime markerInfo(T) orelse return true;
    if (comptime hasDeinit(T)) return false;
    return engineRepresentationIsBorrowed(info.engine);
}

/// Compile-checks that `T` is valid as a method argument, with an error that
/// names `context`. Owning wrappers and converters whose decode or engine
/// representation owns storage cannot be arguments: arguments are call-scoped
/// borrowed, so declare the borrowed direct type and wrap inside the method.
pub fn checkMethodArgument(comptime T: type, comptime context: []const u8) void {
    if (comptime !methodArgumentIsBorrowed(T)) @compileError(std.fmt.comptimePrint(
        "{s}: type '{s}' owns decoded or engine storage and cannot be a method argument. " ++
            "Method arguments are call-scoped borrowed; use the borrowed direct type and wrap " ++
            "explicitly inside the method.",
        .{ context, @typeName(T) },
    ));
}

/// True when `Engine` owns no storage: a canonical scalar, a plain builtin, or a
/// non-`RefCounted` object pointer. Managed, heap, and packed builtins and
/// `RefCounted` object pointers own storage.
fn engineRepresentationIsBorrowed(comptime Engine: type) bool {
    if (comptime reflect.objectTarget(Engine) != null) return !reflect.isRefCountedPointer(Engine);
    if (comptime builtins.Variant.typeFor(Engine) == null) return true;
    return comptime bindings.builtins.traits.kindOf(Engine) == .plain;
}

/// Encodes `value` into a Variant with `Variant.initDeclared`'s copy/ownership
/// behavior, through the marker's `toEngine` first. `value` is `T` or a form
/// `initDeclared` accepts for it (a coercible literal, a pointer to an extending
/// class); a converter requires an exact `T`.
pub fn encodeVariant(comptime T: type, value: anytype, out: *builtins.Variant) void {
    checkSupported(T, .variant, "encodeVariant");
    if (comptime markerInfo(T)) |info| {
        const engine_value = info.marker.toEngine(value);
        defer deinitEngine(info.engine, engine_value);
        out.* = builtins.Variant.initDeclared(info.engine, engine_value);
        return;
    }
    out.* = builtins.Variant.initDeclared(T, value);
}

/// Encodes `T` into one ptrcall return slot through the marker's `toEngine`
/// first. Direct types delegate to `ptrcall.encodeDirectPtr`; the slot receives
/// its own value/reference, so consumers have nothing to release.
pub fn encodePtrcallSlot(comptime T: type, value: T, raw: ?*anyopaque) void {
    checkSupported(T, .ptrcall, "encodePtrcallSlot");
    if (comptime markerInfo(T)) |info| {
        ptrcall.encodeDirectPtr(info.engine, info.marker.toEngine(value), raw);
        return;
    }
    ptrcall.encodeDirectPtr(T, value, raw);
}

/// True when `T` can be passed to `borrowVariant`: a direct type or converter
/// whose engine representation is borrowed rather than owned (a canonical
/// scalar, a plain builtin, or an object pointer). A borrowed `RefCounted` view
/// pins no reference, so the caller must keep its own reference alive during the
/// engine call. Owned storage needs `encodeVariant`.
pub fn canBorrowVariant(comptime T: type) bool {
    if (comptime markerInfo(T)) |info| return canBorrowEngine(info.engine);
    return builtins.Variant.canBorrow(T);
}

fn canBorrowEngine(comptime Engine: type) bool {
    if (comptime !builtins.Variant.canBorrow(Engine)) return false;
    if (comptime reflect.objectTarget(Engine) != null) return true;
    return comptime bindings.builtins.traits.kindOf(Engine) == .plain;
}

/// Writes a borrowed Variant view of `value` into `out`, with `encodeVariant`'s
/// accepted forms. The view is valid only during one synchronous engine call:
/// never deinit or store it. Types `canBorrowVariant` rejects must use
/// `encodeVariant`.
pub fn borrowVariant(comptime T: type, value: anytype, out: *builtins.Variant) void {
    checkSupported(T, .variant, "borrowVariant");
    if (comptime !canBorrowVariant(T)) @compileError(std.fmt.comptimePrint(
        "borrowVariant: type '{s}' has engine-owned Variant storage and cannot be borrowed; use encodeVariant",
        .{@typeName(T)},
    ));
    if (comptime markerInfo(T)) |info| {
        out.* = borrowVariantValue(info.engine, info.marker.toEngine(value));
        return;
    }
    out.* = borrowVariantValue(T, value);
}

/// Borrowed Variant view of `value`, normalized to `T` for
/// `Variant.initDeclared`; aliases `value` or its engine value, never deinit.
fn borrowVariantValue(comptime T: type, value: anytype) builtins.Variant {
    if (comptime reflect.objectTarget(T) != null) return borrowObjectVariant(T, value);
    const local: T = coerceBorrowValue(T, value);
    return builtins.Variant.borrow(T, &local).get();
}

/// Borrowed object Variant for a declared object pointer `T`: engine subclass
/// pointers pass, extension instances reduce to their engine base (except
/// extension-declared types, which require that exact instance). A null nullable
/// value becomes `Variant.nil`.
fn borrowObjectVariant(comptime T: type, value: anytype) builtins.Variant {
    const ValueT = @TypeOf(value);
    const target = comptime reflect.objectTarget(T) orelse unreachable;
    if (comptime ValueT == T) return builtins.Variant.borrow(T, value).get();
    if (comptime ValueT == @TypeOf(null)) {
        if (comptime !target.optional) @compileError(
            "borrowVariant: " ++ @typeName(T) ++ " is not optional; pass an object pointer instead of null",
        );
        return builtins.Variant.nil;
    }

    const value_target = comptime reflect.objectTarget(ValueT) orelse @compileError(std.fmt.comptimePrint(
        "borrowVariant expects an object pointer for {s}, found: {s}",
        .{ @typeName(T), @typeName(ValueT) },
    ));
    const ValueClass = value_target.class;
    const Class = target.class;

    if (comptime target.kind == .extension) {
        if (comptime ValueClass != Class) @compileError(std.fmt.comptimePrint(
            "borrowVariant: extension class '{s}' requires that exact instance; found: {s}",
            .{ @typeName(Class), @typeName(ValueT) },
        ));
    } else {
        const EngineBase = comptime reflect.EngineBaseType(ValueClass);
        if (comptime !reflect.inheritsFrom(EngineBase, Class)) @compileError(std.fmt.comptimePrint(
            "borrowVariant expects '{s}', but '{s}' resolves to engine base '{s}', which does not extend it",
            .{ @typeName(Class), @typeName(ValueT), @typeName(EngineBase) },
        ));
    }

    const raw: *ValueClass = if (comptime value_target.optional) blk: {
        const item = value orelse return builtins.Variant.nil;
        break :blk @constCast(@as(*const ValueClass, @ptrCast(item)));
    } else @constCast(@as(*const ValueClass, @ptrCast(value)));

    // The declared extension type keeps its exact instance; `Variant.borrow`
    // reduces it to the engine base. Engine-declared types reduce here.
    const object: *Class = if (comptime target.kind == .extension or value_target.kind == .engine)
        @ptrCast(raw)
    else
        @ptrCast(reflect.engineBasePointer(ValueClass, raw));
    const declared: T = object;
    return builtins.Variant.borrow(T, declared).get();
}

/// Normalizes `value` to `T` under the declared-type rules of
/// `Variant.initDeclared`, without creating an owning Variant.
fn coerceBorrowValue(comptime T: type, value: anytype) T {
    const ValueT = @TypeOf(value);
    if (comptime ValueT == T) return value;
    if (comptime ValueT == comptime_int) return @as(T, value);
    if (comptime ValueT == comptime_float) return @as(T, value);
    if (comptime ValueT == @TypeOf(.enum_literal) and @typeInfo(T) == .@"enum") {
        return @as(T, value);
    }
    @compileError(std.fmt.comptimePrint(
        "borrowVariant expects {s}, found: {s}",
        .{ @typeName(T), @typeName(ValueT) },
    ));
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
    if (comptime direct.variant or direct.ptrcall) return null;

    const Marker = comptime conversion_marker.find(T) orelse return null;
    validateMarker(T, Marker);
    return .{
        .marker = Marker,
        .engine = comptime conversion_marker.MarkerEngine(Marker),
    };
}

fn directSupport(comptime T: type) Support {
    if (comptime T == void) return .{ .variant = false, .ptrcall = false };

    const variant = comptime T == builtins.Variant or builtins.Variant.typeFor(T) != null;
    const has_ptrcall = comptime variant or isSingleItemPointer(T);
    return .{ .variant = variant, .ptrcall = has_ptrcall };
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
    if (comptime hasDeinit(E)) {
        var copy = value;
        copy.deinit();
    }
}

/// True for types whose `deinit` declaration owns their decoded storage. A
/// declared type says it owns decodes this way; pointers, optionals, and scalars
/// have no declarations.
fn hasDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "deinit"),
        else => false,
    };
}

fn validateMarker(comptime T: type, comptime Marker: type) void {
    const Engine = comptime conversion_marker.MarkerEngine(Marker);
    if (comptime !@hasDecl(Marker, "toEngine")) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': missing '.toEngine'.",
        .{ @typeName(T), @typeName(Marker) },
    ));
    if (comptime !@hasDecl(Marker, "fromEngine")) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': missing '.fromEngine'.",
        .{ @typeName(T), @typeName(Marker) },
    ));

    const EngineSupport = directSupport(Engine);
    if (comptime !EngineSupport.variant and !EngineSupport.ptrcall) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': '.Engine' must have a Variant or " ++
            "ptrcall representation; found '{s}'.",
        .{ @typeName(T), @typeName(Marker), @typeName(Engine) },
    ));
    if (comptime Engine == builtins.Variant) @compileError(std.fmt.comptimePrint(
        "Type '{s}' has an invalid Conversion marker '{s}': '.Engine' cannot be Variant itself; " ++
            "Variant has transparent storage, so choose a concrete representation type.",
        .{ @typeName(T), @typeName(Marker) },
    ));

    validateConverterFn(T, Marker, "toEngine", @TypeOf(Marker.toEngine), T, Engine);
    validateConverterFn(T, Marker, "fromEngine", @TypeOf(Marker.fromEngine), Engine, T);
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
        .ptrcall => "ptrcall",
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

const ptrcall = @import("ptrcall.zig");
const builtins = @import("builtins/builtins.zig");
const conversion_marker = @import("annotations/conversion.zig");
const reflect = @import("reflect/reflect.zig");
