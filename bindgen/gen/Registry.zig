//! Type-name analysis for the generated wrapper.
//!
//! The GDExtension headers use a `GDExtension` prefix for almost every public
//! type. The wrapper exposes those types without the prefix so the generated
//! file reads like regular Zig code. This module computes that mapping once,
//! up front, so individual emitters never have to allocate or guess.
//!
//! Allocation strategy: the whole table is built from exactly two allocations
//! (the entry array and one scratch buffer holding every mangled name). Search
//! is a linear scan; the interface JSON only contains ~150 types, so this is
//! cheaper than maintaining a hash map and its per-key allocations.

const Registry = @This();

entries: []const Entry,

pub const Kind = enum {
    @"enum",
    handle,
    alias,
    @"struct",
    function,
};

pub const Entry = struct {
    /// Type name as written in the interface JSON and the C header.
    raw: []const u8,
    /// Name exposed by the generated wrapper.
    zig: []const u8,
    kind: Kind,
};

pub const InitError = error{
    DuplicateTypeName,
    DuplicateWrapperName,
};

pub fn init(
    arena: Allocator,
    types: []const InterfaceJson.TypeDecl,
    strip_deprecation: bool,
) (Allocator.Error || InitError)!Registry {
    var active_count: usize = 0;
    var raw_bytes: usize = 0;
    for (types) |t| {
        if (isStripped(t, strip_deprecation)) continue;
        active_count += 1;
        raw_bytes += t.name.len;
    }

    const entries = try arena.alloc(Entry, active_count);

    // Every mangled name is a subsequence of the raw name, so one buffer of
    // `sum(raw.len)` bytes is always large enough. Using the raw size for each
    // slot keeps the slices stable while the in-place passes shrink the text.
    const names = try arena.alloc(u8, raw_bytes);

    var offset: usize = 0;
    var entry_index: usize = 0;
    for (types) |t| {
        if (isStripped(t, strip_deprecation)) continue;

        const kind = kindOf(t.data);
        const slot = names[offset..][0..t.name.len];
        @memcpy(slot, t.name);
        const len = mangleInPlace(slot, removalsFor(kind));
        entries[entry_index] = .{
            .raw = t.name,
            .zig = slot[0..len],
            .kind = kind,
        };
        offset += t.name.len;
        entry_index += 1;
    }

    // Duplicate C names would make lookups ambiguous; duplicate wrapper names
    // would produce an invalid Zig file. Report both instead of generating
    // silently broken output.
    for (entries, 0..) |entry, i| {
        for (entries[0..i]) |previous| {
            if (std.mem.eql(u8, entry.raw, previous.raw)) {
                std.log.err("Duplicate type `{s}` in interface JSON", .{entry.raw});
                return error.DuplicateTypeName;
            }
            if (std.mem.eql(u8, entry.zig, previous.zig)) {
                std.log.err("Types `{s}` and `{s}` both map to wrapper name `{s}`", .{ previous.raw, entry.raw, entry.zig });
                return error.DuplicateWrapperName;
            }
        }
    }

    return .{ .entries = entries };
}

pub fn get(self: Registry, raw: []const u8) ?Entry {
    for (self.entries) |entry| {
        if (std.mem.eql(u8, entry.raw, raw)) return entry;
    }
    return null;
}

fn isStripped(t: InterfaceJson.TypeDecl, strip_deprecation: bool) bool {
    return strip_deprecation and t.deprecated != null;
}

pub fn kindOf(data: InterfaceJson.TypeDecl.Data) Kind {
    return switch (data) {
        .@"enum" => .@"enum",
        .handle => .handle,
        .alias => .alias,
        .@"struct" => .@"struct",
        .function => .function,
    };
}

/// Prefixes removed from a type name. Enum names keep any `GD` part (matching
/// the wrapper names that existed before this refactor); every other kind also
/// strips `GD`, which is what turns `GDObjectInstanceID` into
/// `ObjectInstanceID`.
pub fn removalsFor(kind: Kind) []const []const u8 {
    return switch (kind) {
        .@"enum" => &.{"GDExtension"},
        else => &.{ "GDExtension", "GD" },
    };
}

/// Applies every removal to `buf` in place and returns the new length.
/// Each pass only moves bytes towards the front, so the buffer may alias the
/// source while shrinking.
pub fn mangleInPlace(buf: []u8, removals: []const []const u8) usize {
    var len = buf.len;
    for (removals) |needle| {
        len = removeAll(buf[0..len], needle);
    }
    return len;
}

fn removeAll(buf: []u8, needle: []const u8) usize {
    std.debug.assert(needle.len > 0);
    var src: usize = 0;
    var dst: usize = 0;
    while (src + needle.len <= buf.len) {
        if (std.mem.eql(u8, buf[src..][0..needle.len], needle)) {
            src += needle.len;
        } else {
            buf[dst] = buf[src];
            dst += 1;
            src += 1;
        }
    }
    while (src < buf.len) : (src += 1) {
        buf[dst] = buf[src];
        dst += 1;
    }
    return dst;
}

/// Mangles a name that may not be part of the registry (for example a
/// deprecation replacement target) into a caller-provided buffer.
pub fn mangleToBuf(name: []const u8, buf: []u8) error{NameTooLong}![]const u8 {
    if (buf.len < name.len) return error.NameTooLong;
    @memcpy(buf[0..name.len], name);
    return buf[0..mangleInPlace(buf[0..name.len], &.{ "GDExtension", "GD" })];
}

test "mangling drops the C prefix" {
    var buf: [64]u8 = undefined;

    try std.testing.expectEqualStrings("VariantType", try mangleToBuf("GDExtensionVariantType", &buf));
    try std.testing.expectEqualStrings("ObjectInstanceID", try mangleToBuf("GDObjectInstanceID", &buf));
    try std.testing.expectEqualStrings("ClassCreationInfo5", try mangleToBuf("GDExtensionClassCreationInfo5", &buf));
    try std.testing.expectEqualStrings("VariantPtr", try mangleToBuf("GDExtensionVariantPtr", &buf));
    try std.testing.expectEqualStrings("Foo", try mangleToBuf("GDFoo", &buf));
}

test "mangling applies removals sequentially" {
    var buf: [64]u8 = undefined;

    // Removing `GDExtension` leaves `GD...`, which the second pass removes.
    try std.testing.expectEqualStrings("Bar", try mangleToBuf("GDExtensionGDGDGDExtensionBar", &buf));
    try std.testing.expectEqualStrings("", try mangleToBuf("GD", &buf));
}

test "registry maps enum names without removing GD" {
    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionVariantType", .data = .{ .@"enum" = .{ .values = &.{} } } },
        .{ .name = "GDExtensionVariantPtr", .data = .{ .handle = .{} } },
    };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const registry = try init(arena_state.allocator(), &types, false);

    try std.testing.expectEqualStrings("VariantType", registry.get("GDExtensionVariantType").?.zig);
    try std.testing.expectEqualStrings("VariantPtr", registry.get("GDExtensionVariantPtr").?.zig);
    try std.testing.expect(registry.get("GDExtensionVariantType").?.kind == .@"enum");
    try std.testing.expect(registry.get("GDExtensionVariantPtr").?.kind == .handle);
    try std.testing.expect(registry.get("Missing") == null);
}

test "strip_deprecation omits deprecated types" {
    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionKeep", .data = .{ .@"struct" = .{ .members = &.{} } } },
        .{
            .name = "GDExtensionDrop",
            .data = .{ .@"struct" = .{ .members = &.{} } },
            .deprecated = .{ .since = "4.0" },
        },
    };

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const full = try init(arena_state.allocator(), &types, false);
    try std.testing.expect(full.get("GDExtensionDrop") != null);

    const stripped = try init(arena_state.allocator(), &types, true);
    try std.testing.expect(stripped.get("GDExtensionKeep") != null);
    try std.testing.expect(stripped.get("GDExtensionDrop") == null);
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const InterfaceJson = @import("../InterfaceJson.zig");
