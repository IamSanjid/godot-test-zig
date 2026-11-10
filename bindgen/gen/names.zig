//! Shared identifier and file-name helpers for the bindgen emitters.

pub fn snake(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .snake, raw);
}

pub fn camel(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .camel, raw);
}

pub fn pascal(arena: Allocator, raw: []const u8) ![]const u8 {
    return convert(arena, .pascal, raw);
}

/// Name of the cached function-pointer variable for a method/operator.
pub fn pointer(arena: Allocator, raw: []const u8) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try casez.writeConvert(&fixed, .camel, raw);
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

pub fn writeMemberIdent(writer: *Io.Writer, name: []const u8) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try casez.writeConvert(&fixed, .snake, name);
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
    try casez.writeConvert(&fixed, .snake, raw_name);
    try writeRawIdent(writer, fixed.buffered());
}

fn writeSnakeIdent(writer: *Io.Writer, raw_name: []const u8) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try casez.writeConvert(&fixed, .snake, raw_name);
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

fn convert(arena: Allocator, comptime config: casez.Config, raw: []const u8) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    casez.writeConvert(&fixed, config, raw) catch return error.IdentifierTooLong;
    return arena.dupe(u8, fixed.buffered());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const casez = @import("casez");
const common = @import("common.zig");
