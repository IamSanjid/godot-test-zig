//! `Constants` declaration marker: a class's integer constants, enums, and
//! bitfield flag structs. See docs/classdb.md.

/// One engine integer constant, ready for
/// `classdb_register_extension_class_integer_constant`.
pub const Entry = struct {
    /// Engine enum name; empty for a loose constant.
    enum_name: [:0]const u8,
    /// Engine constant name (ALL_CAPS).
    name: [:0]const u8,
    value: i64,
    is_bitfield: bool,
};

/// Wraps a struct of constant declarations as a class marker.
///
/// An integer declaration is one loose constant, an `enum` declaration expands
/// to one constant per variant under the enum name, and a `bitpack struct`
/// declaration expands to one bitfield constant per bool field.
pub fn Constants(comptime p_decls: type) type {
    const info = @typeInfo(p_decls);
    if (info != .@"struct" or info.@"struct".is_tuple or info.@"struct".layout == .@"bitpack") {
        @compileError("Constants expects a struct of declarations, e.g. " ++
            "`Constants(struct { pub const MAX = 1; })`; found: " ++ @typeName(p_decls));
    }
    if (info.@"struct".field_names.len != 0) {
        @compileError("Constants expects declarations only, but '" ++ @typeName(p_decls) ++ "' has fields");
    }

    const resolved: []const Entry = buildEntries(p_decls);
    if (resolved.len == 0) @compileError("Constants marker declares no constants; declare an integer, enum, or bitflag struct");

    return struct {
        pub const decls = p_decls;
        pub const entries = resolved;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.constants;
    };
}

/// True when `OtherT` is a type produced by `Constants`.
fn isConstants(comptime OtherT: type) bool {
    if (!marker_kind.is(OtherT, .constants)) return false;
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "decls") or !@hasDecl(OtherT, "entries")) return false;
    return OtherT == Constants(OtherT.decls);
}

/// Constants declared by `T`'s `Constants` markers, in declaration order.
pub fn findConstants(comptime T: type) []const Entry {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("Expected a class struct, found: " ++ @typeName(T));

        const decl_names = @typeInfo(T).@"struct".decl_names;
        var total: usize = 0;
        for (decl_names) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isConstants(Decl)) continue;
            total += Decl.entries.len;
        }

        var entries: [total]Entry = undefined;
        var count: usize = 0;
        for (decl_names) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isConstants(Decl)) continue;
            for (Decl.entries) |entry| {
                entries[count] = entry;
                count += 1;
            }
        }

        checkDuplicateConstants(T, entries[0..count]);
        const out = entries[0..count].*;
        return &out;
    }
}

/// Inspector hint metadata derived from a Zig value type alone, independent of
/// any class's `Constants` markers.
pub const TypeHint = struct {
    /// Hint string for the inspector: "Idle:0,Running:3" or "First:1,Second:2".
    hint_string: [:0]const u8,
    is_bitfield: bool,
};

/// `is_bitfield` for a value type that carries inspector hint metadata: an
/// exhaustive enum (false) or a bitpack struct (true). Null for every other
/// type, so callers can answer without scanning anything.
fn hintIsBitfield(comptime Value: type) ?bool {
    return switch (@typeInfo(Value)) {
        // A non-exhaustive enum has no value set, so it cannot be declared in a
        // Constants marker; a property may still use the type, without a hint.
        .@"enum" => |enum_info| if (enum_info.mode == .exhaustive) false else null,
        .@"struct" => |struct_info| if (struct_info.backing_integer != null) true else null,
        else => null,
    };
}

/// Inspector hint metadata for `Value` itself: an exhaustive enum yields its
/// variants and a bitpack struct its bool flag fields. A type with no hintable
/// entries yields null. No class or `Constants` marker is consulted.
pub fn typeHint(comptime Value: type) ?TypeHint {
    return comptime blk: {
        @setEvalBranchQuota(1_000_000);
        const is_bitfield = hintIsBitfield(Value) orelse break :blk null;

        if (is_bitfield) {
            const struct_info = @typeInfo(Value).@"struct";
            var entries: [bitfieldFlagCount(Value)]HintEntry = undefined;
            var count: usize = 0;
            for (struct_info.field_names, struct_info.field_types) |field_name, FieldT| {
                if (!isFlagField(field_name, FieldT)) continue;
                entries[count] = .{
                    .label = naming.comptimeConvert(.godot, .type, field_name),
                    .value = bitfieldMask(Value, field_name),
                };
                count += 1;
            }
            if (count == 0) break :blk null;
            break :blk .{
                .hint_string = buildHintString(entries[0..count]),
                .is_bitfield = true,
            };
        }

        const enum_info = @typeInfo(Value).@"enum";
        if (enum_info.field_names.len == 0) break :blk null;
        var entries: [enum_info.field_names.len]HintEntry = undefined;
        for (enum_info.field_names, enum_info.field_values, 0..) |field_name, field_value, i| {
            entries[i] = .{
                .label = naming.comptimeConvert(.godot, .type, field_name),
                .value = integerValue(field_value),
            };
        }
        break :blk .{
            .hint_string = buildHintString(entries[0..]),
            .is_bitfield = false,
        };
    };
}

/// A `Value` declaration found in a class's `Constants` markers: the raw
/// declaration name inside the marker and whether it registers as a bitfield.
pub const EnumName = struct {
    /// Engine enum/bitfield name: the declaration name inside the Constants struct.
    name: [:0]const u8,
    is_bitfield: bool,
};

/// Name under which `Value` is declared inside a `Constants` marker on `Class`,
/// or null when it is not declared there.
///
/// `Value` must be an exhaustive enum or a bitpack struct: only those two
/// declaration shapes register under an engine enum name, and other types
/// answer null without scanning. A `Value` declared more than once is
/// ambiguous and rejected at compile time.
pub fn findEnumName(comptime Class: type, comptime Value: type) ?EnumName {
    return comptime blk: {
        @setEvalBranchQuota(1_000_000);
        const hint = typeHint(Value) orelse break :blk null;
        const is_bitfield = hint.is_bitfield;

        if (@typeInfo(Class) != .@"struct") @compileError(
            "Expected a class struct, found: " ++ @typeName(Class),
        );

        var found: ?FoundDeclaration = null;
        for (@typeInfo(Class).@"struct".decl_names) |marker_name| {
            const Decl = @field(Class, marker_name);
            if (@TypeOf(Decl) != type or !isConstants(Decl)) continue;
            for (@typeInfo(Decl.decls).@"struct".decl_names) |item_name| {
                const Item = @field(Decl.decls, item_name);
                if (@TypeOf(Item) != type) continue;
                if (Item != Value) continue;
                if (found) |first| @compileError(std.fmt.comptimePrint(
                    "Type '{s}' is declared more than once in the Constants markers on '{s}': " ++
                        "'{s}.{s}' and '{s}.{s}'. A property value type must map to exactly one declaration; " ++
                        "remove or rename one.",
                    .{ @typeName(Value), @typeName(Class), first.marker, first.item, marker_name, item_name },
                ));
                found = .{ .marker = marker_name, .item = item_name };
            }
        }
        const declaration = found orelse break :blk null;

        break :blk .{
            .name = declaration.item,
            .is_bitfield = is_bitfield,
        };
    };
}

/// A `Value` declaration found while scanning: the `Constants` marker's
/// declaration name on the class and the declaration name inside that marker.
const FoundDeclaration = struct {
    marker: [:0]const u8,
    item: [:0]const u8,
};

/// One `Label:value` pair of a hint string.
const HintEntry = struct {
    label: [:0]const u8,
    value: i64,
};

/// True for a bitpack field that contributes a hint flag. Non-bool fields carry
/// data or padding rather than a flag, and `_`-prefixed fields are layout
/// padding; both are skipped for hints. `Constants` registration rejects
/// non-bool, non-`_` flag fields instead.
fn isFlagField(comptime field_name: []const u8, comptime FieldT: type) bool {
    return !std.mem.startsWith(u8, field_name, "_") and FieldT == bool;
}

/// Bool flags a bitpack value type contributes.
fn bitfieldFlagCount(comptime Flags: type) usize {
    const info = @typeInfo(Flags).@"struct";
    var count: usize = 0;
    for (info.field_names, info.field_types) |field_name, FieldT| {
        if (isFlagField(field_name, FieldT)) count += 1;
    }
    return count;
}

/// Joins entries as `Label:value,...` into one sentinel-terminated comptime
/// string. The format string and the alternating label/value argument tuple are
/// assembled at comptime because their length depends on the declaration.
fn buildHintString(comptime entries: []const HintEntry) [:0]const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        if (entries.len == 0) return "";

        const unit = "{s}:{d}";
        const fmt_len = entries.len * unit.len + (entries.len - 1);
        var fmt_buf: [fmt_len]u8 = undefined;
        var pos: usize = 0;
        for (entries, 0..) |_, i| {
            if (i != 0) {
                fmt_buf[pos] = ',';
                pos += 1;
            }
            @memcpy(fmt_buf[pos..][0..unit.len], unit);
            pos += unit.len;
        }

        var arg_types: [entries.len * 2]type = undefined;
        for (0..entries.len) |i| {
            arg_types[i * 2] = [:0]const u8;
            arg_types[i * 2 + 1] = i64;
        }
        const Args = @Tuple(&arg_types);
        var args: Args = undefined;
        for (entries, 0..) |entry, i| {
            args[i * 2] = entry.label;
            args[i * 2 + 1] = entry.value;
        }

        return std.fmt.comptimePrint(fmt_buf[0..pos], args);
    }
}

fn buildEntries(comptime decls: type) []const Entry {
    comptime {
        var entries: [entryCount(decls)]Entry = undefined;
        var count: usize = 0;
        for (@typeInfo(decls).@"struct".decl_names) |decl_name| {
            collectDeclaration(decls, decl_name, &entries, &count);
        }
        const out = entries[0..count].*;
        return &out;
    }
}

/// Upper bound on the entries one `Constants` marker emits. Declaration-shape
/// errors are reported by `collectDeclaration`, which visits every declaration.
fn entryCount(comptime decls: type) usize {
    var total: usize = 0;
    for (@typeInfo(decls).@"struct".decl_names) |decl_name| {
        const Decl = @field(decls, decl_name);
        if (@TypeOf(Decl) != type) {
            total += 1;
            continue;
        }
        total += switch (@typeInfo(Decl)) {
            .@"enum" => |info| info.field_names.len,
            .@"struct" => |info| info.field_names.len,
            else => 1,
        };
    }
    return total;
}

fn collectDeclaration(
    comptime decls: type,
    comptime decl_name: [:0]const u8,
    entries: []Entry,
    count: *usize,
) void {
    const Decl = @field(decls, decl_name);

    if (@TypeOf(Decl) != type) {
        entries[count.*] = .{
            .enum_name = "",
            .name = naming.comptimeConvert(.godot, .constant, decl_name),
            .value = integerValue(Decl),
            .is_bitfield = false,
        };
        count.* += 1;
        return;
    }

    switch (@typeInfo(Decl)) {
        .@"enum" => |info| {
            if (info.mode == .nonexhaustive) @compileError(
                declLabel(decls, decl_name) ++ " must be an exhaustive enum; a non-exhaustive enum has no value set to register",
            );
            for (info.field_names, info.field_values) |field_name, field_value| {
                entries[count.*] = .{
                    .enum_name = decl_name,
                    .name = naming.comptimeConvert(.godot, .constant, field_name),
                    .value = integerValue(field_value),
                    .is_bitfield = false,
                };
                count.* += 1;
            }
        },
        .@"struct" => |info| {
            if (info.backing_integer == null) @compileError(
                declLabel(decls, decl_name) ++ " must be a bitpack struct to register a bitfield; " ++
                    "found a plain struct: " ++ @typeName(Decl),
            );
            for (info.field_names, info.field_types) |field_name, FieldT| {
                if (std.mem.startsWith(u8, field_name, "_")) continue;
                if (FieldT != bool) @compileError(
                    declLabel(decls, decl_name) ++ "." ++ field_name ++ " must be a bool bitfield flag; " ++
                        "found: " ++ @typeName(FieldT),
                );
                entries[count.*] = .{
                    .enum_name = decl_name,
                    .name = naming.comptimeConvert(.godot, .constant, field_name),
                    .value = bitfieldMask(Decl, field_name),
                    .is_bitfield = true,
                };
                count.* += 1;
            }
        },
        else => @compileError(
            declLabel(decls, decl_name) ++ " must be an integer, an enum, or a bitpack struct; " ++
                "found: " ++ @typeName(Decl),
        ),
    }
}

fn declLabel(comptime decls: type, comptime decl_name: []const u8) []const u8 {
    return "Constants(" ++ @typeName(decls) ++ ")." ++ decl_name;
}

/// Canonical `i64` constant value. `u64` bits above `i64` are carried in the
/// sign bit, matching the API contract for 64-bit constants.
fn integerValue(comptime value: anytype) i64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .comptime_int => @intCast(value),
        .int => |info| if (info.signedness == .unsigned and info.bits == 64)
            @bitCast(@as(u64, value))
        else
            @intCast(value),
        else => @compileError("Constant must be an integer, found: " ++ @typeName(@TypeOf(value))),
    };
}

/// The bit a bitfield flag occupies, read from the real bitpack layout so
/// padding anywhere in the declaration is handled.
fn bitfieldMask(comptime Flags: type, comptime field_name: [:0]const u8) i64 {
    const Backing = @typeInfo(Flags).@"struct".backing_integer.?;
    var flags: Flags = @bitCast(@as(Backing, 0));
    @field(flags, field_name) = true;
    const mask: Backing = @bitCast(flags);
    return integerValue(mask);
}

fn checkDuplicateConstants(comptime T: type, entries: []const Entry) void {
    for (entries, 0..) |entry, i| {
        for (entries[i + 1 ..]) |other| {
            if (std.mem.eql(u8, entry.enum_name, other.enum_name) and
                std.mem.eql(u8, entry.name, other.name))
            {
                @compileError(std.fmt.comptimePrint(
                    "Class '{s}' declares constant '{s}' twice{}. Rename one declaration.",
                    .{
                        @typeName(T),
                        entry.name,
                        if (entry.enum_name.len != 0) " in enum '" ++ entry.enum_name ++ "'" else "",
                    },
                ));
            }
        }
    }
}

const std = @import("std");

const naming = @import("naming");

const marker_kind = @import("marker.zig");
