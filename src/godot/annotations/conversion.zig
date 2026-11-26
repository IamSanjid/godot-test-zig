//! `Conversion` type-attached marker. See docs/conversion.md for the contract.

/// Declares the conversion of value type `T` to `spec.engine` and back.
///
/// Attach the marker to `T` under any declaration name, for example
/// `pub const GodotConversion = Conversion(.{ ... });`. Its spec keys are
/// `.engine`, `.to_engine`, and `.from_engine`; `conversion.zig` validates the
/// owner signatures and engine support.
pub fn Conversion(comptime spec: anytype) type {
    const Spec = @TypeOf(spec);
    const spec_info = switch (@typeInfo(Spec)) {
        .@"struct" => |info| info,
        else => @compileError(std.fmt.comptimePrint(
            "Conversion spec must be a struct literal with .engine, .to_engine, and .from_engine fields; found '{s}'. " ++
                "Use godot.annotations.Conversion(.{{ ... }}).",
            .{@typeName(Spec)},
        )),
    };

    comptime {
        for (spec_info.field_names) |name| {
            if (!std.mem.eql(u8, name, "engine") and
                !std.mem.eql(u8, name, "to_engine") and
                !std.mem.eql(u8, name, "from_engine"))
            {
                @compileError(std.fmt.comptimePrint(
                    "Conversion spec has unknown field '{s}'; expected only .engine, .to_engine, and .from_engine.",
                    .{name},
                ));
            }
        }
        if (spec_info.field_names.len != 3) {
            @compileError(std.fmt.comptimePrint(
                "Conversion spec must have exactly .engine, .to_engine, and .from_engine; found {d} field(s).",
                .{spec_info.field_names.len},
            ));
        }
    }

    const engine_value = spec.engine;
    if (comptime @TypeOf(engine_value) != type) {
        @compileError(std.fmt.comptimePrint(
            "Conversion spec field '.engine' must be a type; found '{s}'.",
            .{@typeName(@TypeOf(engine_value))},
        ));
    }

    const to_engine_value = spec.to_engine;
    if (comptime @typeInfo(@TypeOf(to_engine_value)) != .@"fn") {
        @compileError(std.fmt.comptimePrint(
            "Conversion spec field '.to_engine' must be a function; found '{s}'.",
            .{@typeName(@TypeOf(to_engine_value))},
        ));
    }

    const from_engine_value = spec.from_engine;
    if (comptime @typeInfo(@TypeOf(from_engine_value)) != .@"fn") {
        @compileError(std.fmt.comptimePrint(
            "Conversion spec field '.from_engine' must be a function; found '{s}'.",
            .{@typeName(@TypeOf(from_engine_value))},
        ));
    }

    return struct {
        pub const Engine = engine_value;
        pub const toEngine = to_engine_value;
        pub const fromEngine = from_engine_value;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.conversion;
    };
}

/// Returns the engine type of a `Conversion` marker type. Validates the
/// marker shape only; the owner-dependent function signatures are checked by
/// `conversion.zig`.
pub fn MarkerEngine(comptime Marker: type) type {
    if (comptime !canHoldDecls(Marker)) @compileError(std.fmt.comptimePrint(
        "Conversion marker '{s}' is not a marker type; use " ++
            "godot.annotations.Conversion(.{{ .engine = <supported type>, .to_engine = <fn>, .from_engine = <fn> }}).",
        .{@typeName(Marker)},
    ));
    if (!@hasDecl(Marker, "Engine")) @compileError(std.fmt.comptimePrint(
        "Conversion marker '{s}' is missing '.Engine'.",
        .{@typeName(Marker)},
    ));

    const Engine = Marker.Engine;
    if (comptime @TypeOf(Engine) != type) @compileError(std.fmt.comptimePrint(
        "Conversion marker '{s}' field '.Engine' must be a type; found '{s}'.",
        .{ @typeName(Marker), @typeName(@TypeOf(Engine)) },
    ));
    return Engine;
}

/// Returns `T`'s `Conversion` marker, or null when `T` declares none. The
/// declaration name is free: discovery scans `T`'s declarations for a type with
/// the conversion marker identity. More than one is a compile error.
pub fn find(comptime T: type) ?type {
    if (comptime !canHoldDecls(T)) return null;

    comptime {
        var found: ?type = null;
        for (declNames(T)) |decl_name| {
            const Decl = @field(T, decl_name);
            if (!isConversionMarker(Decl)) continue;
            if (found != null) @compileError(std.fmt.comptimePrint(
                "Type '{s}' declares more than one Conversion marker; keep a single declaration.",
                .{@typeName(T)},
            ));
            found = Decl;
        }
        return found;
    }
}

/// True when `Decl` is a type produced by `Conversion`.
fn isConversionMarker(comptime Decl: anytype) bool {
    if (@TypeOf(Decl) != type) return false;
    if (!marker_kind.is(Decl, .conversion)) return false;
    if (@typeInfo(Decl) != .@"struct") return false;
    if (!@hasDecl(Decl, "Engine") or !@hasDecl(Decl, "toEngine") or !@hasDecl(Decl, "fromEngine")) return false;
    if (@TypeOf(Decl.Engine) != type) return false;
    if (@typeInfo(@TypeOf(Decl.toEngine)) != .@"fn") return false;
    if (@typeInfo(@TypeOf(Decl.fromEngine)) != .@"fn") return false;
    return Decl == Conversion(.{
        .engine = Decl.Engine,
        .to_engine = Decl.toEngine,
        .from_engine = Decl.fromEngine,
    });
}

fn declNames(comptime T: type) []const []const u8 {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| info.decl_names,
        .@"enum" => |info| info.decl_names,
        .@"union" => |info| info.decl_names,
        .@"opaque" => |info| info.decl_names,
        else => &.{},
    };
}

/// True for types that can carry declarations.
fn canHoldDecls(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };
}

const std = @import("std");

const marker_kind = @import("marker.zig");
