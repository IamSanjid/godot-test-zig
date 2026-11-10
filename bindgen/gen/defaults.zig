//! Parsing and emission for `extension_api.json` default-value literals.

pub const Call = struct {
    name: []const u8,
    args: [16][]const u8 = undefined,
    count: usize = 0,
};

pub fn parseCall(value: []const u8) ?Call {
    const open = std.mem.indexOfScalar(u8, value, '(') orelse return null;
    if (!std.mem.endsWith(u8, value, ")")) return null;
    const name = std.mem.trim(u8, value[0..open], " ");
    const body = value[open + 1 .. value.len - 1];
    var call = Call{ .name = name };
    var args = std.mem.splitScalar(u8, body, ',');
    while (args.next()) |arg| {
        if (call.count == call.args.len) return null;
        call.args[call.count] = std.mem.trim(u8, arg, " ");
        call.count += 1;
    }
    if (call.count == 1 and call.args[0].len == 0) call.count = 0;
    return call;
}

pub fn writeMathLiteral(writer: *Io.Writer, prefix: []const u8, raw_type: []const u8, value: []const u8) !bool {
    const call = parseCall(value) orelse return false;
    if (!std.mem.eql(u8, call.name, raw_type)) return false;

    if (std.mem.eql(u8, raw_type, "Color")) {
        if (call.count != 4) return false;
        try writer.print("{s}Color{{ .r = {s}, .g = {s}, .b = {s}, .a = {s} }}", .{ prefix, call.args[0], call.args[1], call.args[2], call.args[3] });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Vector2") or std.mem.eql(u8, raw_type, "Vector2i")) {
        if (call.count != 2) return false;
        try writer.print("{s}{s}{{ .x = {s}, .y = {s} }}", .{ prefix, raw_type, call.args[0], call.args[1] });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Vector3") or std.mem.eql(u8, raw_type, "Vector3i")) {
        if (call.count != 3) return false;
        try writer.print("{s}{s}{{ .x = {s}, .y = {s}, .z = {s} }}", .{ prefix, raw_type, call.args[0], call.args[1], call.args[2] });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Vector4") or std.mem.eql(u8, raw_type, "Vector4i")) {
        if (call.count != 4) return false;
        try writer.print("{s}{s}{{ .x = {s}, .y = {s}, .z = {s}, .w = {s} }}", .{ prefix, raw_type, call.args[0], call.args[1], call.args[2], call.args[3] });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Rect2") or std.mem.eql(u8, raw_type, "Rect2i")) {
        if (call.count != 4) return false;
        const vector_type = if (std.mem.eql(u8, raw_type, "Rect2i")) "Vector2i" else "Vector2";
        try writer.print("{s}{s}{{ .position = {s}{s}{{ .x = {s}, .y = {s} }}, .size = {s}{s}{{ .x = {s}, .y = {s} }} }}", .{
            prefix, raw_type, prefix, vector_type, call.args[0], call.args[1], prefix, vector_type, call.args[2], call.args[3],
        });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Transform2D")) {
        if (call.count != 6) return false;
        try writer.print("{s}Transform2D{{ .x = {s}Vector2{{ .x = {s}, .y = {s} }}, .y = {s}Vector2{{ .x = {s}, .y = {s} }}, .origin = {s}Vector2{{ .x = {s}, .y = {s} }} }}", .{
            prefix, prefix, call.args[0], call.args[1], prefix, call.args[2], call.args[3], prefix, call.args[4], call.args[5],
        });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Transform3D")) {
        if (call.count != 12) return false;
        try writer.print("{s}Transform3D{{ .basis = {s}Basis{{ .x = {s}Vector3{{ .x = {s}, .y = {s}, .z = {s} }}, .y = {s}Vector3{{ .x = {s}, .y = {s}, .z = {s} }}, .z = {s}Vector3{{ .x = {s}, .y = {s}, .z = {s} }} }}, .origin = {s}Vector3{{ .x = {s}, .y = {s}, .z = {s} }} }}", .{
            prefix, prefix, prefix, call.args[0], call.args[1], call.args[2], prefix, call.args[3], call.args[4], call.args[5], prefix, call.args[6], call.args[7], call.args[8], prefix, call.args[9], call.args[10], call.args[11],
        });
        return true;
    }
    return false;
}

pub fn writeStringLiteral(
    writer: *Io.Writer,
    prefix: []const u8,
    raw_type: []const u8,
    value: []const u8,
    dispatcher: []const u8,
) !bool {
    if (std.mem.eql(u8, raw_type, "StringName")) {
        const contents = unquote(value) orelse return false;
        try writer.print("{s}StringName.fromComptimeLatin1({s}, \"", .{ prefix, dispatcher });
        try names.writeEscaped(writer, contents);
        try writer.writeAll("\")");
        return true;
    }
    if (std.mem.eql(u8, raw_type, "String")) {
        const contents = unquote(value) orelse return false;
        try writer.print("{s}String.fromStringName({s}, {s}StringName.fromComptimeLatin1({s}, \"", .{ prefix, dispatcher, prefix, dispatcher });
        try names.writeEscaped(writer, contents);
        try writer.writeAll("\"))");
        return true;
    }
    if (std.mem.eql(u8, raw_type, "NodePath")) {
        const call = parseCall(value) orelse return false;
        if (!std.mem.eql(u8, call.name, "NodePath") or call.count != 1) return false;
        const contents = unquote(call.args[0]) orelse return false;
        if (contents.len == 0) {
            try writer.print("{s}NodePath.init({s})", .{ prefix, dispatcher });
            return true;
        }
        try writer.print("{s}NodePath.fromString({s}, {s}String.fromStringName({s}, {s}StringName.fromComptimeLatin1({s}, \"", .{ prefix, dispatcher, prefix, dispatcher, prefix, dispatcher });
        try names.writeEscaped(writer, contents);
        try writer.writeAll("\")))");
        return true;
    }
    return false;
}

pub fn writeVariantLiteral(writer: *Io.Writer, prefix: []const u8, value: []const u8, dispatcher: []const u8) !bool {
    if (std.mem.eql(u8, value, "null")) {
        try writer.print("{s}Variant.nil()", .{prefix});
        return true;
    }
    if (!isInteger(value)) return false;
    try writer.print("blk: {{ var value: i64 = {s}; break :blk {s}Variant.fromPtr({s}, i64, &value); }}", .{ value, prefix, dispatcher });
    return true;
}

pub fn isEmptyConstructor(raw_type: []const u8, value: []const u8) bool {
    const call = parseCall(value) orelse return false;
    return call.count == 0 and std.mem.eql(u8, call.name, raw_type);
}

pub fn writeEmptyContainer(writer: *Io.Writer, prefix: []const u8, raw_type: []const u8, value: []const u8, dispatcher: []const u8) !bool {
    if (std.mem.eql(u8, raw_type, "Array") and std.mem.eql(u8, value, "[]")) {
        try writer.print("{s}Array.init({s})", .{ prefix, dispatcher });
        return true;
    }
    if (std.mem.eql(u8, raw_type, "Dictionary") and std.mem.eql(u8, value, "{}")) {
        try writer.print("{s}Dictionary.init({s})", .{ prefix, dispatcher });
        return true;
    }
    return false;
}

fn unquote(value: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, value, "&\"") and std.mem.endsWith(u8, value, "\"")) {
        return value[2 .. value.len - 1];
    }
    if (std.mem.startsWith(u8, value, "\"") and std.mem.endsWith(u8, value, "\"")) {
        return value[1 .. value.len - 1];
    }
    return null;
}

fn isInteger(value: []const u8) bool {
    if (value.len == 0) return false;
    var index: usize = 0;
    if (value[0] == '-') index = 1;
    if (index == value.len) return false;
    while (index < value.len) : (index += 1) {
        if (!std.ascii.isDigit(value[index])) return false;
    }
    return true;
}

const std = @import("std");
const Io = std.Io;

const names = @import("names.zig");
