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
    };
}

/// True when `OtherT` is a type produced by `Constants`.
fn isConstants(comptime OtherT: type) bool {
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

// Compile-only coverage; analyzed on every build.

const Fixture = struct {
    pub const ClassConstants = Constants(struct {
        pub const MAX_HEALTH = 100;
        pub const maxSpeed: u32 = 42;
        pub const State = enum(i32) { idle, running = 3 };
        pub const Flags = bitpack struct(u32) {
            first: bool = false,
            second: bool = false,
            _pad0: u30 = 0,
        };
    });

    /// A second marker proves the declaration name is free and entries append.
    pub const More = Constants(struct {
        pub const EXTRA = 5;
    });
};

fn checkConstantDiscovery() void {
    const entries = findConstants(Fixture);
    if (entries.len != 7) @compileError("findConstants must expand enum and bitfield declarations across markers");

    if (!std.mem.eql(u8, entries[0].name, "MAX_HEALTH")) @compileError("constant names are converted to engine constants");
    if (entries[0].enum_name.len != 0) @compileError("loose constants have no enum name");
    if (entries[0].value != 100) @compileError("loose constants keep their value");
    if (!std.mem.eql(u8, entries[1].name, "MAX_SPEED")) @compileError("camelCase constant names are converted");
    if (entries[1].enum_name.len != 0) @compileError("loose constants have no enum name");

    if (!std.mem.eql(u8, entries[2].enum_name, "State")) @compileError("enum variants carry their enum name");
    if (!std.mem.eql(u8, entries[2].name, "IDLE")) @compileError("enum variants are converted to engine constants");
    if (entries[2].value != 0) @compileError("enum variants keep their value");
    if (!std.mem.eql(u8, entries[3].name, "RUNNING")) @compileError("enum variants are converted to engine constants");
    if (entries[3].value != 3) @compileError("explicit enum values are preserved");

    if (!std.mem.eql(u8, entries[4].enum_name, "Flags")) @compileError("bitfield flags carry their enum name");
    if (!std.mem.eql(u8, entries[4].name, "FIRST")) @compileError("bitfield flags are converted to engine constants");
    if (entries[4].value != 1 or !entries[4].is_bitfield) @compileError("the first bitfield flag is bit 0");
    if (entries[5].value != 2) @compileError("the second bitfield flag is bit 1");
    if (entries[5].is_bitfield == false) @compileError("bitfield flags report is_bitfield");

    if (!std.mem.eql(u8, entries[6].name, "EXTRA")) @compileError("a second marker's entries must append");
    if (entries[6].value != 5) @compileError("a second marker's values must be preserved");

    if (findConstants(NoConstants).len != 0) @compileError("classes without a Constants marker must report none");
}

const NoConstants = struct {};

comptime {
    checkConstantDiscovery();
}

test "constants are discovered in declaration order" {
    const entries = comptime findConstants(Fixture);
    try std.testing.expectEqual(@as(usize, 7), entries.len);
    try std.testing.expectEqualStrings("MAX_HEALTH", entries[0].name);
    try std.testing.expectEqualStrings("RUNNING", entries[3].name);
    try std.testing.expectEqual(@as(i64, 2), entries[5].value);
    try std.testing.expectEqualStrings("EXTRA", entries[6].name);
}

test "bitfield bits come from the bitpack layout" {
    const Rear = struct {
        pub const Bits = Constants(struct {
            pub const Flags = bitpack struct(u32) {
                _pad0: u2 = 0,
                third: bool = false,
                _pad1: u29 = 0,
            };
        });
    };
    const entries = comptime findConstants(Rear);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(@as(i64, 4), entries[0].value);
}

const std = @import("std");

const naming = @import("naming");
