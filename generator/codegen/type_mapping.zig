//! Conversion helpers for codegen wrappers.
//!
//! Codegen-facing types and binding-call types are distinct. This module is the
//! single place that decides how a value crosses that boundary.

pub const ResolvedType = resolver.ResolvedType;
pub const TypeContext = resolver.TypeContext;
pub const Scope = resolver.Scope;

pub fn resolve(
    class_resolver: *const resolver.ClassResolver,
    raw: []const u8,
    context: TypeContext,
) !ResolvedType {
    return class_resolver.resolveFor(raw, context, .class_file);
}

pub fn resolveBuiltin(
    class_resolver: *const resolver.ClassResolver,
    raw: []const u8,
    context: TypeContext,
) !ResolvedType {
    return class_resolver.resolveFor(raw, context, .builtin_file);
}

pub fn resolveUtility(
    class_resolver: *const resolver.ClassResolver,
    raw: []const u8,
    context: TypeContext,
) !ResolvedType {
    return class_resolver.resolveFor(raw, context, .utility_file);
}

/// Writes a value expression for an argument going from codegen to bindings.
pub fn writeArg(writer: *Io.Writer, resolved: ResolvedType, expr: []const u8) !void {
    switch (resolved.kind) {
        .class_ptr => try writer.print("@ptrCast({s})", .{expr}),
        .builtin, .variant => try writer.print("{s}.toBinding()", .{expr}),
        .primitive, .native_ptr, .@"enum", .void => try writer.writeAll(expr),
    }
}

/// Writes a value expression for an options field going to bindings.
pub const writeOptionValue = writeArg;

/// Writes `self.<field>` through the normal option-value conversion.
pub fn writeSelfOptionValue(
    writer: *Io.Writer,
    arena: Allocator,
    resolved: ResolvedType,
    field_name: []const u8,
) !void {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    try names.writeMemberIdent(&fixed, field_name);
    const expr = try std.fmt.allocPrint(arena, "self.{s}", .{fixed.buffered()});
    try writeOptionValue(writer, resolved, expr);
}

/// Writes a comptime-known default value in codegen type space.
pub fn writeDefaultValue(
    writer: *Io.Writer,
    class_resolver: *const resolver.ClassResolver,
    raw_type: []const u8,
    default_value: []const u8,
    scope: Scope,
) !bool {
    if (!defaults.canInlineDefault(raw_type, default_value)) return false;
    if (try defaults.writeMathLiteral(writer, "builtins.", raw_type, default_value)) return true;

    const resolved = try class_resolver.resolveFor(raw_type, .argument, scope);
    switch (resolved.kind) {
        .primitive => {
            try writer.writeAll(default_value);
            return true;
        },
        .@"enum" => {
            try writer.writeAll("@as(");
            try writer.writeAll(resolved.zig);
            if (resolved.is_bitfield) {
                try writer.print(", @bitCast(@as(u{d}, ", .{resolved.bitfield_bits});
                try writer.writeAll(default_value);
                try writer.writeAll(")))");
            } else {
                try writer.writeAll(", @fromBackingInt(@intCast(");
                try writer.writeAll(default_value);
                try writer.writeAll(")))");
            }
            return true;
        },
        else => return false,
    }
}

/// Writes a value expression for a binding return value coming back to codegen.
pub fn writeReturn(writer: *Io.Writer, resolved: ResolvedType, expr: []const u8) !void {
    switch (resolved.kind) {
        .class_ptr => {
            if (std.mem.startsWith(u8, resolved.zig, "?*")) {
                try writer.print("if ({s}) |ptr| @ptrCast(ptr) else null", .{expr});
            } else {
                try writer.print("@ptrCast({s})", .{expr});
            }
        },
        .builtin, .variant => try writer.print("{s}.fromBinding({s})", .{ resolved.zig, expr }),
        .primitive, .native_ptr, .@"enum", .void => try writer.writeAll(expr),
    }
}

pub fn isVoid(resolved: ResolvedType) bool {
    return resolved.kind == .void;
}

pub fn bindingClassPath(arena: Allocator, class: *const ExtensionApiJson.Class) ![]const u8 {
    if (class.api_type) |api_type| {
        return std.fmt.allocPrint(arena, "classes.{s}.{s}", .{ api_type, class.name });
    }
    return std.fmt.allocPrint(arena, "classes.{s}", .{class.name});
}

pub fn writeBindingClassPath(writer: *Io.Writer, class: *const ExtensionApiJson.Class) !void {
    try writer.writeAll("bindings.classes.");
    if (class.api_type) |api_type| {
        try writer.print("{s}.", .{api_type});
    }
    try writer.writeAll(class.name);
}

pub fn writeBindingBuiltinPath(writer: *Io.Writer, name: []const u8) !void {
    try writer.print("bindings.builtins.{s}", .{name});
}

pub fn writeCodegenClassPath(writer: *Io.Writer, class: *const ExtensionApiJson.Class) !void {
    try writer.writeAll("classes.");
    if (class.api_type) |api_type| {
        try writer.print("{s}.", .{api_type});
    }
    try writer.writeAll(class.name);
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const resolver = @import("../model/resolver.zig");
const defaults = @import("../model/defaults.zig");
const names = @import("../model/names.zig");
const ExtensionApiJson = @import("../model/ExtensionApiJson.zig");
