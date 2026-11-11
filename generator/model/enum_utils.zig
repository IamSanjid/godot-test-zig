//! Shared enum variant-name helpers for the interface and extension API
//! emitters.

pub const extra_prefixes = [_][]const u8{ "ERROR_", "FLAGS_", "FLAG_", "INITIALIZATION_", "ERR_" };

/// Strips the common prefix and one of the well-known Godot prefixes.
pub fn variantName(name: []const u8, prefix_len: usize) []const u8 {
    var rest = name[prefix_len..];
    for (extra_prefixes) |prefix| {
        if (rest.len > prefix.len and std.mem.startsWith(u8, rest, prefix)) {
            rest = rest[prefix.len..];
            break;
        }
    }
    return rest;
}

/// Longest common prefix ending on a word boundary. Works with any slice whose
/// elements have a `name` field (`InterfaceJson.EnumValue`, global enum values).
pub fn commonPrefixLen(values: anytype) usize {
    if (values.len == 0) return 0;

    var len = values[0].name.len;
    for (values[1..]) |value| {
        len = std.mem.indexOfDiff(u8, values[0].name[0..len], value.name) orelse len;
    }
    while (len > 0 and values[0].name[len - 1] != '_') len -= 1;
    return len;
}

test "common prefix stripping" {
    const values = [_]struct { name: []const u8 }{
        .{ .name = "JOY_BUTTON_A" },
        .{ .name = "JOY_BUTTON_B" },
        .{ .name = "JOY_BUTTON_INVALID" },
    };
    try std.testing.expectEqual(@as(usize, "JOY_BUTTON_".len), commonPrefixLen(&values));
    try std.testing.expectEqualStrings("A", variantName("JOY_BUTTON_A", "JOY_BUTTON_".len));
}

const std = @import("std");
