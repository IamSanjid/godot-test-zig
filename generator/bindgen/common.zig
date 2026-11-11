//! Bindgen emission helpers: documentation comments, deprecation notes and
//! C-to-Zig type expressions.
//!
//! Keeping type rendering in one place is important: struct members, function
//! arguments, return values and type aliases all have to agree on how a raw
//! C type maps into Zig, otherwise the generated file ends up with a mix of
//! `gdi.X` and wrapper types.

pub const writeIdent = names.writeIdent;

pub fn writeDesc(
    writer: *Io.Writer,
    maybe_desc: ?InterfaceJson.Description,
    comptime indent: usize,
    comptime comment_slashes: usize,
) !void {
    const desc = maybe_desc orelse return;
    for (desc) |line| {
        try writer.print("{s}", .{@as([indent]u8, @splat(' '))});
        try writer.print("{s}", .{@as([comment_slashes]u8, @splat('/'))});
        try writer.print(" {s}\n", .{line});
    }
}

pub fn writeDeprecated(
    writer: *Io.Writer,
    registry: Registry,
    maybe_deprecated: ?InterfaceJson.Deprecated,
    comptime indent: usize,
    comptime comment_slashes: usize,
) !void {
    const deprecated = maybe_deprecated orelse return;

    try writer.print("{s}", .{@as([indent]u8, @splat(' '))});
    try writer.print("{s}", .{@as([comment_slashes]u8, @splat('/'))});
    try writer.print(" Deprecated since {s}", .{deprecated.since});

    if (deprecated.replace_with) |replace_with| {
        try writer.print(", in favor of {s}", .{replacementName(registry, replace_with)});
    }

    if (deprecated.message) |msg| {
        try writer.print(". {s}", .{msg});
        if (msg.len == 0 or msg[msg.len - 1] != '.') try writer.writeAll(".");
    } else {
        try writer.writeAll(".");
    }
    try writer.writeAll("\n");
}

fn replacementName(registry: Registry, raw: []const u8) []const u8 {
    if (registry.get(raw)) |entry| return entry.zig;

    // Future interface versions may mention a replacement that is not itself
    // declared in `types`. Fall back to the same prefix stripping.
    const S = struct {
        var buf: [128]u8 = undefined;
    };
    return Registry.mangleToBuf(raw, &S.buf) catch raw;
}

/// Writes the Zig spelling of a raw C type as it appears in the interface JSON.
///
/// Resolution order:
/// 1. the primitive C type table (`uint32_t`, `const char*`, ...),
/// 2. a wrapper type declared by the interface JSON,
/// 3. a C pointer to either of the above.
///
/// Pointer handling mirrors the GDExtension ABI:
/// - pointers to wrapper structs/functions become nullable Zig pointers,
///   because the C API uses `NULL` for e.g. empty property/method lists,
/// - pointers to handles and primitive values stay C pointers (`[*c]`),
///   matching how the translated interface module already spells them.
pub fn writeType(writer: *Io.Writer, registry: Registry, raw_type: []const u8) !void {
    const raw = std.mem.trim(u8, raw_type, " ");
    if (raw.len == 0) return error.EmptyTypeName;

    if (c_aliases.get(raw)) |mapped| {
        try writer.writeAll(mapped);
        return;
    }
    if (registry.get(raw)) |entry| {
        try writer.writeAll(entry.zig);
        return;
    }

    var base = raw;
    var is_const = false;
    if (std.mem.startsWith(u8, base, "const ")) {
        is_const = true;
        base = base["const ".len..];
    }

    var pointer_depth: usize = 0;
    while (std.mem.endsWith(u8, base, "*")) {
        pointer_depth += 1;
        base = std.mem.trimEnd(u8, base[0 .. base.len - 1], " ");
    }

    if (pointer_depth == 0) {
        // Qualified or unknown bare type. Resolve it through the wrapper when
        // possible; otherwise fall back to the translated C declaration.
        if (resolveBase(registry, base)) |resolved| {
            try writer.writeAll(resolved.name);
        } else {
            try writeGdiFallback(writer, base);
        }
        return;
    }

    // Outer pointer levels are always plain C pointers. In C, a leading
    // `const` qualifies the innermost pointee, so only the last level carries
    // it.
    var level: usize = 1;
    while (level < pointer_depth) : (level += 1) {
        try writer.writeAll("[*c]");
    }

    const resolved = resolveBase(registry, base);
    if (resolved) |r| {
        try writePointer(writer, r, is_const);
    } else {
        try writer.writeAll(if (is_const) "[*c]const " else "[*c]");
        try writeGdiFallback(writer, base);
    }
}

fn writeGdiFallback(writer: *Io.Writer, base: []const u8) !void {
    if (!std.zig.isValidId(base)) {
        std.log.err("invalid C type name `{s}`", .{base});
        return error.InvalidTypeName;
    }
    try writer.print("gdi.{s}", .{base});
}

const Resolved = struct {
    name: []const u8,
    kind: Registry.Kind,
};

fn resolveBase(registry: Registry, base: []const u8) ?Resolved {
    if (c_aliases.get(base)) |mapped| return .{ .name = mapped, .kind = .alias };
    if (registry.get(base)) |entry| return .{ .name = entry.zig, .kind = entry.kind };
    return null;
}

fn writePointer(writer: *Io.Writer, resolved: Resolved, is_const: bool) !void {
    switch (resolved.kind) {
        .@"struct", .function => {
            try writer.writeAll(if (is_const) "?*const " else "?*");
        },
        else => {
            try writer.writeAll(if (is_const) "[*c]const " else "[*c]");
        },
    }
    try writer.writeAll(resolved.name);
}

/// Raw C spellings that map to Zig primitives or C pointers to primitives.
/// Anything described by a wrapper type in the JSON is resolved through the
/// registry instead, so it must not be listed here.
pub const c_aliases = std.StaticStringMap([]const u8).initComptime(.{
    .{ "GDExtensionBool", "bool" },
    .{ "size_t", "usize" },
    .{ "uint64_t", "u64" },
    .{ "uint32_t", "u32" },
    .{ "uint16_t", "u16" },
    .{ "uint8_t", "u8" },
    .{ "int64_t", "i64" },
    .{ "int32_t", "i32" },
    .{ "int16_t", "i16" },
    .{ "int8_t", "i8" },
    .{ "float", "f32" },
    .{ "double", "f64" },
    .{ "bool", "bool" },
    .{ "char", "u8" },
    .{ "void", "void" },
    .{ "void*", "?*anyopaque" },
    .{ "const void*", "?*const anyopaque" },
    .{ "const char*", "[*c]const u8" },
    .{ "const wchar*", "[*c]const u16" },
    .{ "const char32_t*", "[*c]const u32" },
    .{ "uint32_t*", "[*c]u32" },
    .{ "uint16_t*", "[*c]u16" },
    .{ "uint8_t*", "[*c]u8" },
    .{ "int32_t*", "[*c]i32" },
    .{ "int16_t*", "[*c]i16" },
    .{ "int8_t*", "[*c]i8" },
});

test "primitive and wrapper type names" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const types = [_]InterfaceJson.TypeDecl{
        .{ .name = "GDExtensionPropertyInfo", .data = .{ .@"struct" = .{ .members = &.{} } } },
        .{ .name = "GDExtensionCallError", .data = .{ .@"struct" = .{ .members = &.{} } } },
        .{ .name = "GDExtensionConstTypePtr", .data = .{ .handle = .{} } },
        .{ .name = "GDExtensionBool", .data = .{ .alias = .{ .type = "uint8_t" } } },
        .{ .name = "GDExtensionClassSet", .data = .{ .function = .{ .arguments = &.{} } } },
    };
    const registry = try Registry.init(arena_state.allocator(), &types, false);

    const cases = [_]struct { raw: []const u8, expected: []const u8 }{
        .{ .raw = "GDExtensionBool", .expected = "bool" },
        .{ .raw = "GDExtensionPropertyInfo", .expected = "PropertyInfo" },
        .{ .raw = "const GDExtensionPropertyInfo", .expected = "PropertyInfo" },
        .{ .raw = "GDExtensionPropertyInfo*", .expected = "?*PropertyInfo" },
        .{ .raw = "const GDExtensionPropertyInfo*", .expected = "?*const PropertyInfo" },
        .{ .raw = "GDExtensionPropertyInfo**", .expected = "[*c]?*PropertyInfo" },
        .{ .raw = "GDExtensionCallError*", .expected = "?*CallError" },
        .{ .raw = "GDExtensionClassSet*", .expected = "?*ClassSet" },
        .{ .raw = "const GDExtensionConstTypePtr*", .expected = "[*c]const ConstTypePtr" },
        .{ .raw = "GDExtensionBool*", .expected = "[*c]bool" },
        .{ .raw = "size_t", .expected = "usize" },
        .{ .raw = "uint32_t*", .expected = "[*c]u32" },
        .{ .raw = "int64_t", .expected = "i64" },
        .{ .raw = "void", .expected = "void" },
        .{ .raw = "void*", .expected = "?*anyopaque" },
        .{ .raw = "const char*", .expected = "[*c]const u8" },
    };

    for (cases) |case| {
        var aw: Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeType(&aw.writer, registry, case.raw);
        try std.testing.expectEqualStrings(case.expected, aw.writer.buffered());
    }
}

test "unknown bare types fall back to gdi" {
    const registry: Registry = .{ .entries = &.{} };
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeType(&aw.writer, registry, "mystery_t");
    try std.testing.expectEqualStrings("gdi.mystery_t", aw.writer.buffered());
}

const std = @import("std");
const Io = std.Io;

const InterfaceJson = @import("../model/InterfaceJson.zig");
const Registry = @import("Registry.zig");
const names = @import("../model/names.zig");
