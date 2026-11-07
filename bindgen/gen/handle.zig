//! Opaque handle typedefs. The translated C module already provides the
//! correct pointer/const pointer type, so the wrapper only renames it.

pub fn emit(writer: *Io.Writer, registry: Registry, t: InterfaceJson.TypeDecl) !void {
    std.debug.assert(t.data == .handle);
    const zig_name = registry.get(t.name).?.zig;

    try common.writeDeprecated(writer, registry, t.deprecated, 0, 3);
    try common.writeDesc(writer, t.description, 0, 3);
    try writer.print("pub const {s} = gdi.{s};\n", .{ zig_name, t.name });
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../InterfaceJson.zig");
const Registry = @import("Registry.zig");
const common = @import("common.zig");
