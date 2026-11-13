//! Shared identifier and file-name helpers for the generator.

pub fn writeFile(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .file, name);
}

pub fn writeConstant(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .constant, name);
}

pub fn writeEnumVariant(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .enum_variant, name);
}

pub fn writeArgument(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .argument, name);
}

pub fn writeField(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .field, name);
}

pub fn writeProperty(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .property, name);
}

pub fn writeMethod(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .method, name);
}

pub fn writeFunc(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .func, name);
}

pub fn writeTypeName(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .type, name);
}

pub fn writeSignal(writer: *Io.Writer, name: []const u8) !void {
    try writeConverted(writer, .zig, .signal, name);
}

pub fn snake(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .file, raw);
}

pub fn camel(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .method, raw);
}

pub fn pascal(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .type, raw);
}

/// Name of the cached function-pointer variable for a method/operator.
pub fn pointer(arena: Allocator, raw: []const u8) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    naming.writeConvert(&fixed, .zig, .method, raw) catch return error.IdentifierTooLong;
    try fixed.writeAll("_ptr");
    return arena.dupe(u8, fixed.buffered());
}

pub fn writeRawIdent(writer: *Io.Writer, name: []const u8) !void {
    if (std.zig.isValidId(name) and !isPrimitiveName(name)) {
        try writer.writeAll(name);
    } else {
        try writer.print("@\"{s}\"", .{name});
    }
}

/// Whether `name` can be used as a generated member/function identifier.
///
/// Keywords and primitive type names are valid after `writeRawIdent` escapes
/// them as `@"name"`.
pub fn isValidMemberName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (c == '"' or c == '\\' or c == '\n' or c == '\r') return false;
    }
    if (std.zig.isValidId(name)) return true;
    if (std.zig.Token.getKeyword(name) != null) return true;
    return isPrimitiveName(name);
}

pub fn writeMemberIdent(writer: *Io.Writer, name: []const u8) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try naming.writeConvert(&fixed, .zig, .property, name);
    try writeRawIdent(writer, fixed.buffered());
}

fn isPrimitiveName(name: []const u8) bool {
    const primitives = [_][]const u8{
        "anyerror",     "anyopaque",      "anyframe",     "bool",     "c_int",   "c_long",
        "c_longdouble", "c_longlong",     "c_short",      "c_uint",   "c_ulong", "c_ulonglong",
        "c_ushort",     "comptime_float", "comptime_int", "f128",     "f16",     "f32",
        "f64",          "f80",            "isize",        "noreturn", "type",    "u128",
        "u16",          "u32",            "u64",          "u8",       "usize",   "void",
        "undefined",    "null",           "true",         "false",
    };
    for (primitives) |primitive| {
        if (std.mem.eql(u8, name, primitive)) return true;
    }
    return false;
}

/// Writes a prefixed argument identifier (`p_...`) and avoids keyword/shadow
/// collisions with generated function names.
pub fn writeArgName(writer: *Io.Writer, raw_name: []const u8, index: usize) !void {
    if (raw_name.len == 0) {
        try writer.print("arg{d}", .{index});
        return;
    }
    if (std.mem.startsWith(u8, raw_name, "p_")) {
        try writeSnakeIdent(writer, raw_name);
    } else {
        try writePrefixedIdent(writer, "p_", raw_name);
    }
}

pub fn writePrefixedIdent(writer: *Io.Writer, prefix: []const u8, raw_name: []const u8) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try fixed.writeAll(prefix);
    try naming.writeConvert(&fixed, .zig, .argument, raw_name);
    try writeRawIdent(writer, fixed.buffered());
}

fn writeSnakeIdent(writer: *Io.Writer, raw_name: []const u8) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try naming.writeConvert(&fixed, .zig, .argument, raw_name);
    try writeRawIdent(writer, fixed.buffered());
}

pub fn writeEscaped(writer: *Io.Writer, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => try writer.writeByte(c),
        }
    }
}

pub fn writeGodotClassName(writer: *Io.Writer, raw_name: []const u8) !void {
    try writer.writeAll("    pub const GodotClassName = \"");
    try writeEscaped(writer, raw_name);
    try writer.writeAll("\";\n");
}

fn writeConverted(
    writer: *Io.Writer,
    comptime case: naming.Case,
    comptime @"for": @EnumLiteral(),
    name: []const u8,
) !void {
    if (name.len == 0) {
        try writer.writeAll("_");
        return;
    }

    var buf: [128]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    naming.writeConvert(&fixed, case, @"for", name) catch |err| switch (err) {
        error.NoSpaceLeft => return error.IdentifierTooLong,
        else => return err,
    };

    // Trim before validating: a leading underscore can hide a Zig keyword
    // (`_error` -> `error`), which would otherwise be emitted unquoted.
    const converted = std.mem.trim(u8, fixed.buffered(), "_");
    if (converted.len == 0) {
        try writer.writeAll("_");
        return;
    }
    for (converted) |c| {
        if (c == '"' or c == '\\' or c == '\n' or c == '\r') return error.InvalidIdentifier;
    }
    if (std.zig.isValidId(converted)) {
        try writer.writeAll(converted);
    } else {
        try writer.print("@\"{s}\"", .{converted});
    }
}

fn convert(
    arena: Allocator,
    comptime @"for": @EnumLiteral(),
    raw: []const u8,
) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    naming.writeConvert(&fixed, .zig, @"for", raw) catch return error.IdentifierTooLong;
    return arena.dupe(u8, fixed.buffered());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const naming = @import("naming");
