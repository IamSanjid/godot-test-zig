//! Result-initialization policy for binding calls.
//!
//! Builtin values with a C++ constructor/copy/destructor must be constructed
//! before an engine ptrcall writes its result into them. POD builtins and
//! primitives can stay undefined because the engine writes all of their bits.
//! Constructors are a special case: the engine constructor initializes the
//! destination itself.

pub fn resultNeedsInit(raw: []const u8) bool {
    if (std.mem.startsWith(u8, raw, "typedarray::")) return true;
    if (std.mem.startsWith(u8, raw, "typeddictionary::")) return true;

    const names_needing_init = [_][]const u8{
        "String",
        "StringName",
        "NodePath",
        "Callable",
        "Signal",
        "Dictionary",
        "Array",
        "PackedByteArray",
        "PackedInt32Array",
        "PackedInt64Array",
        "PackedFloat32Array",
        "PackedFloat64Array",
        "PackedStringArray",
        "PackedVector2Array",
        "PackedVector3Array",
        "PackedVector4Array",
        "PackedColorArray",
    };
    for (names_needing_init) |name| {
        if (std.mem.eql(u8, raw, name)) return true;
    }
    return false;
}

/// Writes the initializer part of a result declaration:
///
///     var result: T = <this>;
pub fn writeResultInitializer(
    writer: *Io.Writer,
    raw: []const u8,
    zig_type: []const u8,
    dispatcher_expr: []const u8,
) !void {
    if (std.mem.eql(u8, raw, "Variant")) {
        try writer.print("{s}.nil()", .{zig_type});
    } else if (resultNeedsInit(raw)) {
        try writer.print("{s}.init({s})", .{ zig_type, dispatcher_expr });
    } else {
        try writer.writeAll("undefined");
    }
}

const std = @import("std");
const Io = std.Io;
