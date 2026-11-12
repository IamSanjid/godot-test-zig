//! Reflection metadata for generated member and static functions.
//!
//! The metadata entries alias the actual generated functions, so
//! `@TypeOf(@field(Owner.MemberFunctions, "name"))` is a function type and
//! `auto.FunctionOf` can inspect/call it.

const std = @import("std");
const Io = std.Io;
const names_mod = @import("../model/names.zig");

pub fn write(
    writer: *Io.Writer,
    names: []const []const u8,
    static_flags: []const bool,
    count: usize,
    owner: []const u8,
    top_level: bool,
    indent: usize,
) !void {
    std.debug.assert(names.len >= count);
    std.debug.assert(static_flags.len >= count);

    if (top_level) {
        try writer.writeAll("const _self = @This();\n\n");
    }
    const owner_expr = if (top_level) "_self" else owner;

    try writeGroup(writer, "MemberFunctions", names, static_flags, count, owner_expr, indent, false);
    try writeGroup(writer, "StaticFunctions", names, static_flags, count, owner_expr, indent, true);
}

fn writeGroup(
    writer: *Io.Writer,
    group_name: []const u8,
    names: []const []const u8,
    static_flags: []const bool,
    count: usize,
    owner: []const u8,
    indent: usize,
    want_static: bool,
) !void {
    try writeSpaces(writer, indent);
    try writer.print("pub const {s} = struct {{\n", .{group_name});
    for (names[0..count], static_flags[0..count]) |name, is_static| {
        if (is_static != want_static) continue;
        try writeSpaces(writer, indent + 4);
        try writer.writeAll("pub const ");
        try names_mod.writeRawIdent(writer, name);
        try writer.writeAll(" = ");
        try writer.writeAll(owner);
        try writer.writeAll(".");
        try names_mod.writeRawIdent(writer, name);
        try writer.writeAll(";\n");
    }
    try writeSpaces(writer, indent);
    try writer.writeAll("};\n");
}

fn writeSpaces(writer: *Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}
