//! `Signal` declaration marker and typed emit helper. See docs/signals.md.

/// Declares one engine signal. `engine_name` is the engine-facing name; the Zig
/// declaration is only a handle. The second argument is a tuple of
/// `.{ "engine_arg_name", Type }` pairs in engine order, where `Type` is the
/// declared Zig argument type: registration and emit derive its engine type
/// through `godot.conversion`.
pub fn Signal(comptime engine_name: [:0]const u8, comptime p_args: anytype) type {
    validateArgs(engine_name, p_args);
    inline for (p_args) |pair| {
        const context = comptime std.fmt.comptimePrint(
            "Signal '{s}' argument '{s}'",
            .{ engine_name, pair[0] },
        );
        conversion.checkSupported(pair[1], .variant, context);
    }

    return struct {
        pub const name = engine_name;
        /// Argument declarations (`{ name, type }` pairs), in engine order.
        pub const args = p_args;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.signal;

        /// Emits this signal on `owner`. `values` is a positional tuple of
        /// declared Zig values in declaration order; each one is converted to
        /// its derived engine Variant through `godot.conversion`; null optional
        /// values emit as nil.
        pub fn emit(owner: anytype, values: anytype) enums.Error {
            const OwnerT = OwnerType(@TypeOf(owner));
            const ValuesT = @TypeOf(values);
            if (comptime !reflect.isTuple(ValuesT)) @compileError(std.fmt.comptimePrint(
                "Signal '{s}' expects a positional tuple of arguments, e.g. .{{ value, self }}; found: {s}",
                .{ name, @typeName(ValuesT) },
            ));
            if (comptime values.len != args.len) @compileError(std.fmt.comptimePrint(
                "Signal '{s}' expects {d} argument(s), found {d}.",
                .{ name, args.len, values.len },
            ));

            // Owning Variants: the engine reads them during the call only.
            var vargs: [args.len]builtins.Variant = undefined;
            defer for (vargs[0..]) |*variant| variant.deinit();
            inline for (args, 0..) |pair, index| {
                conversion.encodeVariant(pair[1], values[index], &vargs[index]);
            }

            const object = ownerObject(OwnerT, owner);
            return object.emitSignal(builtins.StringName.fromComptimeLatin1(name), vargs);
        }
    };
}

fn validateArgs(comptime engine_name: [:0]const u8, comptime p_args: anytype) void {
    if (engine_name.len == 0) @compileError("Signal name must not be empty");

    if (!reflect.isTuple(@TypeOf(p_args))) @compileError(std.fmt.comptimePrint(
        "Signal '{s}' expects a tuple of .{{ \"name\", Type }} pairs, e.g. .{{ .{{ \"health\", i32 }} }}; found: {s}",
        .{ engine_name, @typeName(@TypeOf(p_args)) },
    ));
    inline for (p_args, 0..) |pair, index| {
        const PairT = @TypeOf(pair);
        if (!reflect.isTuple(PairT) or pair.len != 2) {
            @compileError(std.fmt.comptimePrint(
                "Signal '{s}' argument {d} must be a .{{ \"name\", Type }} pair; found: {s}",
                .{ engine_name, index, @typeName(PairT) },
            ));
        }
        if (@typeInfo(PairT).@"struct".field_types[1] != type) @compileError(std.fmt.comptimePrint(
            "Signal '{s}' argument {d} must end with a type, e.g. .{{ \"health\", i32 }}",
            .{ engine_name, index },
        ));
        const arg_name: [:0]const u8 = pair[0];
        if (arg_name.len == 0) @compileError(std.fmt.comptimePrint(
            "Signal '{s}' argument {d} name must not be empty",
            .{ engine_name, index },
        ));
    }
}

/// The `Signal` markers declared directly on `T`, in declaration order.
pub fn findSignals(comptime T: type) []const type {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("Expected a class struct, found: " ++ @typeName(T));

        const decls = @typeInfo(T).@"struct".decl_names;
        var markers: [decls.len]type = undefined;
        var count: usize = 0;
        for (decls) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isSignal(Decl)) continue;
            markers[count] = Decl;
            count += 1;
        }

        checkDuplicateSignals(T, markers[0..count]);
        const out = markers[0..count].*;
        return &out;
    }
}

/// True when `OtherT` is a type produced by `Signal`.
fn isSignal(comptime OtherT: type) bool {
    if (!marker_kind.is(OtherT, .signal)) return false;
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "name") or !@hasDecl(OtherT, "args")) return false;
    validateArgs(OtherT.name, OtherT.args);
    return OtherT == Signal(OtherT.name, OtherT.args);
}

fn checkDuplicateSignals(comptime T: type, markers: []const type) void {
    for (markers, 0..) |marker, i| {
        const decl_args = marker.args;
        inline for (decl_args, 0..) |pair, arg_index| {
            inline for (0..arg_index) |prev_index| {
                if (std.mem.eql(u8, pair[0], decl_args[prev_index][0])) {
                    @compileError(std.fmt.comptimePrint(
                        "Signal '{s}' on class '{s}' declares argument '{s}' twice.",
                        .{ marker.name, @typeName(T), pair[0] },
                    ));
                }
            }
        }
        for (markers[i + 1 ..]) |other| {
            if (std.mem.eql(u8, marker.name, other.name)) {
                @compileError(std.fmt.comptimePrint(
                    "Class '{s}' declares signal '{s}' twice.",
                    .{ @typeName(T), marker.name },
                ));
            }
        }
    }
}

/// The class an emit owner pointer points at.
fn OwnerType(comptime P: type) type {
    const info = @typeInfo(P);
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("Signal.emit expects a class instance pointer (for example `self`), found: " ++ @typeName(P));
    }
    return info.pointer.child;
}

/// The engine object an emit owner belongs to, through the Base marker chain.
fn ownerObject(comptime T: type, owner: anytype) *classes.core.Object {
    if (comptime !reflect.isClassType(T)) {
        @compileError("Signal.emit expects an engine class or extension class instance, found: " ++ @typeName(T));
    }
    return @ptrCast(reflect.engineBasePointer(T, @as(*const T, owner)));
}

const std = @import("std");

const builtins = @import("../builtins/builtins.zig");
const classes = @import("../classes/classes.zig");
const conversion = @import("../conversion.zig");
const enums = @import("../enums.zig");
const reflect = @import("../reflect/reflect.zig");
const marker_kind = @import("marker.zig");
