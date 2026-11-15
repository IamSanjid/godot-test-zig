//! Shared option-field policy for bindgen and codegen.
//!
//! Renderers still own their type/default syntax, but they must agree on which
//! arguments become options and whether a default is inlined.

const std = @import("std");
const Allocator = std.mem.Allocator;

const defaults = @import("defaults.zig");
const ExtensionApiJson = @import("ExtensionApiJson.zig");

pub const Field = struct {
    argument: ExtensionApiJson.Argument,
    default_value: []const u8,
    inline_default: bool,
};

pub fn hasOptions(arguments: []const ExtensionApiJson.Argument) bool {
    for (arguments) |argument| {
        if (argument.default_value != null) return true;
    }
    return false;
}

pub fn collect(
    arena: Allocator,
    arguments: []const ExtensionApiJson.Argument,
) ![]Field {
    var fields: std.ArrayList(Field) = .empty;
    for (arguments) |argument| {
        const default_value = argument.default_value orelse continue;
        try fields.append(arena, .{
            .argument = argument,
            .default_value = default_value,
            .inline_default = defaults.canInlineDefault(argument.type, default_value),
        });
    }
    return fields.items;
}
