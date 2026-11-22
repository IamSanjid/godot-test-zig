//! `Signal` declaration marker and typed emit helper. See docs/signals.md.

/// Declares one engine signal. `engine_name` is the engine-facing name; the Zig
/// declaration is only a handle. The second argument is a tuple of
/// `.{ "engine_arg_name", Type }` pairs in engine order.
pub fn Signal(comptime engine_name: [:0]const u8, comptime p_args: anytype) type {
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

    return struct {
        pub const name = engine_name;
        /// Argument declarations (`{ name, type }` pairs), in engine order.
        pub const args = p_args;

        /// Emits this signal on `owner`, converting each argument to its
        /// declared engine type. `values` is a positional tuple in declaration
        /// order; null optional values emit as nil.
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
                vargs[index] = builtins.Variant.initDeclared(pair[1], values[index]);
            }

            const object = ownerObject(OwnerT, owner);
            return object.emitSignal(builtins.StringName.fromComptimeLatin1(name), vargs);
        }
    };
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
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "name") or !@hasDecl(OtherT, "args")) return false;
    const info = @typeInfo(@TypeOf(OtherT.args));
    if (info != .@"struct" or !info.@"struct".is_tuple) return false;
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

// Compile-only coverage; analyzed on every build.

const Fixture = struct {
    pub const Extends = classes.core.Node;
    /// A nested namespace with declarations is not a Signal marker.
    pub const Nested = struct {
        pub const MAX_HEALTH = 100;
    };
    pub const HealthChanged = Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*classes.core.Node },
    });
    pub const Pinged = Signal("pinged", .{});

    pub fn methods(self: *const @This()) void {
        _ = self;
    }
};

/// A lookalike without the marker must not be discovered as a signal.
const Lookalike = struct {
    pub const name = "pinged";
    pub const args = .{.{ "health", i32 }};
};

fn checkSignalDeclaration() void {
    const markers = findSignals(Fixture);
    if (markers.len != 2) @compileError("findSignals must report every flat Signal declaration");
    if (!std.mem.eql(u8, markers[0].name, "health_changed")) @compileError("the engine name is the first Signal argument");
    const HealthArgs = markers[0].args;
    if (comptime HealthArgs.len != 2) @compileError("signal arguments must be preserved");
    if (!std.mem.eql(u8, HealthArgs[0][0], "health")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[0][1] != i32) @compileError("signal argument types must be preserved");
    if (!std.mem.eql(u8, HealthArgs[1][0], "source")) @compileError("signal argument names are preserved");
    if (comptime HealthArgs[1][1] != ?*classes.core.Node) @compileError("object argument types must be preserved");
    if (!std.mem.eql(u8, markers[1].name, "pinged")) @compileError("argument-less signals must be discoverable");
    if (comptime markers[1].args.len != 0) @compileError("argument-less signals must report no arguments");

    if (isSignal(Lookalike)) @compileError("a lookalike is not a Signal marker");
    if (isSignal(Fixture.Nested)) @compileError("a nested namespace is not a Signal marker");
}

/// Emit coverage: a real Base marker over a real engine class, so the owner
/// resolution and both argument forms are analyzed.
const EmitFixture = struct {
    pub const Extends = classes.core.Node;
    base: base_mod.Base(Extends) = .{},
    pub const HealthChanged = Signal("health_changed", .{
        .{ "health", i32 },
        .{ "source", ?*classes.core.Node },
    });
    pub const Pinged = Signal("pinged", .{});
};

fn checkEmitPath() void {
    var fixture: EmitFixture = .{};
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, &fixture });
    _ = EmitFixture.HealthChanged.emit(&fixture, .{ 10, null });
    _ = EmitFixture.Pinged.emit(@as(*const EmitFixture, &fixture), .{});
}

comptime {
    checkSignalDeclaration();
    _ = &checkEmitPath;
}

test "signals are discovered in declaration order" {
    const markers = comptime findSignals(Fixture);
    try std.testing.expectEqual(@as(usize, 2), markers.len);
    try std.testing.expectEqualStrings("health_changed", markers[0].name);
    try std.testing.expectEqualStrings("pinged", markers[1].name);
}

const std = @import("std");

const enums = @import("../enums.zig");
const builtins = @import("../builtins/builtins.zig");
const classes = @import("../classes/classes.zig");

const reflect = @import("../reflect/reflect.zig");

const base_mod = @import("base.zig");
