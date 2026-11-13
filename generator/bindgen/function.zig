//! Function-pointer typedefs. Each one becomes an optional function pointer so
//! callers can represent a callback that was not provided (the GDExtension API
//! treats missing callbacks as `NULL`).

pub fn emit(writer: *Io.Writer, registry: Registry, t: InterfaceJson.TypeDecl) !void {
    std.debug.assert(t.data == .function);
    const function = t.data.function;
    const zig_name = registry.get(t.name).?.zig;

    try common.writeDeprecated(writer, registry, t.deprecated, 0, 3);
    try common.writeDesc(writer, t.description, 0, 3);

    try writer.print("pub const {s} = ?*const fn(", .{zig_name});
    for (function.arguments, 0..) |argument, index| {
        if (argument.name) |name| {
            try common.writeArgument(writer, name);
            try writer.writeAll(": ");
        }
        try common.writeType(writer, registry, argument.type);
        if (index + 1 < function.arguments.len) try writer.writeAll(", ");
    }
    try writer.print(") callconv(.{s}) ", .{@tagName(.c)});
    if (function.return_value) |return_value| {
        try common.writeType(writer, registry, return_value.type);
    } else {
        try writer.writeAll("void");
    }
    try writer.writeAll(";\n");
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../model/InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
