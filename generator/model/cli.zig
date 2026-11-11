//! Small command-line helpers shared by the backend option parsers.
//!
//! The generator uses `--name=value` arguments. Kebab-case is canonical, while
//! the underscore spelling is accepted for compatibility with older invocations
//! and with the generated bindings build helper.

pub fn value(args: []const [:0]const u8, name: []const u8) ?[]const u8 {
    return valueAny(args, &.{name});
}

pub fn valueAny(args: []const [:0]const u8, names: []const []const u8) ?[]const u8 {
    for (args) |arg| {
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse continue;
        for (names) |name| {
            if (std.mem.eql(u8, arg[0..eq], name)) {
                return std.mem.trim(u8, arg[eq + 1 ..], &std.ascii.whitespace);
            }
        }
    }
    return null;
}

pub fn required(args: []const [:0]const u8, name: []const u8) ![]const u8 {
    return requiredAny(args, &.{name});
}

pub fn requiredAny(args: []const [:0]const u8, names: []const []const u8) ![]const u8 {
    if (valueAny(args, names)) |result| return result;
    std.log.err("Missing required argument: {s}", .{names[0]});
    return error.MissingField;
}

pub fn parse(comptime T: type, raw: []const u8) !T {
    switch (T) {
        []const u8, []u8 => return raw,
        else => {},
    }
    switch (@typeInfo(T)) {
        .@"enum" => return std.meta.stringToEnum(T, raw) orelse {
            std.log.err("Invalid value for enum type {s}: {s}", .{ @typeName(T), raw });
            return error.InvalidFieldValue;
        },
        .float => return std.fmt.parseFloat(T, raw),
        .int => return std.fmt.parseInt(T, raw),
        .bool => {
            if (std.mem.eql(u8, raw, "true")) return true;
            if (std.mem.eql(u8, raw, "false")) return false;
            std.log.err("Invalid bool value: {s}", .{raw});
            return error.InvalidFieldValue;
        },
        .optional => |opt| {
            if (std.mem.eql(u8, raw, "null")) return null;
            return try parse(opt.child, raw);
        },
        else => @compileError("Type " ++ @typeName(T) ++ " is not supported for command-line parsing."),
    }
}

pub fn parseOptional(
    comptime T: type,
    args: []const [:0]const u8,
    names: []const []const u8,
    default: T,
) !T {
    const raw = valueAny(args, names) orelse return default;
    return try parse(T, raw);
}

const std = @import("std");
