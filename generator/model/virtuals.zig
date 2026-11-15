//! Shared virtual-method metadata policy.
//!
//! A derived class must expose inherited virtuals as well as its own. Child
//! methods win over base entries with the same raw name.

const std = @import("std");
const Allocator = std.mem.Allocator;

const ExtensionApiJson = @import("ExtensionApiJson.zig");
const resolver = @import("resolver.zig");

pub const Entry = struct {
    method: *const ExtensionApiJson.ClassMethod,
    required: bool,
};

pub fn collect(
    arena: Allocator,
    class_resolver: *const resolver.ClassResolver,
    info: *const resolver.Info,
) ![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    var seen: [4096][]const u8 = undefined;
    var seen_count: usize = 0;

    var current: ?*const resolver.Info = info;
    while (current) |class_info| {
        for (class_info.class.methods) |*method| {
            if (!method.is_virtual) continue;
            if (hasName(seen[0..seen_count], method.name)) continue;
            seen[seen_count] = method.name;
            seen_count += 1;
            try entries.append(arena, .{
                .method = method,
                .required = method.is_required,
            });
        }
        current = class_resolver.baseInfo(class_info);
    }

    return entries.items;
}

fn hasName(names: []const []const u8, name: []const u8) bool {
    for (names) |existing| {
        if (std.mem.eql(u8, existing, name)) return true;
    }
    return false;
}
