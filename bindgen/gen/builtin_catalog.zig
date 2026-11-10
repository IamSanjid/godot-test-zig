//! Shared builtin-type catalog.
//!
//! A builtin is generated when it is declared in `builtin_classes`, or when it
//! exists only in `builtin_class_sizes` and has a matching custom file. The
//! class-backed `Object` type therefore lives only in the class bindings.

pub const Entry = struct {
    name: []const u8,
    class: ?*const ExtensionApiJson.BuiltinClass,
    size: usize,
};

pub const BuiltinCatalog = struct {
    entries: []const Entry,

    pub fn init(arena: Allocator, io: Io, api: ExtensionApiJson, options: Options) !BuiltinCatalog {
        const sizes = api.sizesFor(options.builtin_build_conf) orelse {
            std.log.err("No builtin_class_sizes entry for {s}", .{@tagName(options.builtin_build_conf)});
            return error.MissingBuildConfiguration;
        };

        var entries: [256]Entry = undefined;
        var count: usize = 0;
        for (api.builtin_classes) |*class| {
            if (isPrimitive(class.name)) continue;
            const size = findSize(sizes, class.name) orelse continue;
            if (size == 0) continue;
            entries[count] = .{ .name = class.name, .class = class, .size = size };
            count += 1;
        }
        for (sizes) |size_entry| {
            if (isPrimitive(size_entry.name) or isDeclaredBuiltin(api, size_entry.name)) continue;
            if (size_entry.size == 0) continue;
            if (!try hasCustom(arena, io, size_entry.name)) continue;
            entries[count] = .{ .name = size_entry.name, .class = null, .size = size_entry.size };
            count += 1;
        }

        return .{ .entries = try arena.dupe(Entry, entries[0..count]) };
    }

    pub fn isGenerated(self: BuiltinCatalog, name: []const u8) bool {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return true;
        }
        return false;
    }
};

pub fn isPrimitive(name: []const u8) bool {
    return std.mem.eql(u8, name, "Nil") or
        std.mem.eql(u8, name, "bool") or
        std.mem.eql(u8, name, "int") or
        std.mem.eql(u8, name, "float");
}

fn isDeclaredBuiltin(api: ExtensionApiJson, name: []const u8) bool {
    for (api.builtin_classes) |class| {
        if (std.mem.eql(u8, class.name, name)) return true;
    }
    return false;
}

fn hasCustom(arena: Allocator, io: Io, name: []const u8) !bool {
    const file_name = try std.mem.concat(arena, u8, &.{ try names.snake(arena, name), ".zig" });
    const relative_path = try std.fmt.allocPrint(arena, "builtins/{s}", .{file_name});
    return (try custom_code.readForOutput(arena, io, relative_path)) != null;
}

fn findSize(sizes: []const ExtensionApiJson.Size, name: []const u8) ?usize {
    for (sizes) |size| {
        if (std.mem.eql(u8, size.name, name)) return size.size;
    }
    return null;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const custom_code = @import("custom.zig");
const names = @import("names.zig");
const ExtensionApiJson = @import("../ExtensionApiJson.zig");
const Options = @import("../Options.zig");
