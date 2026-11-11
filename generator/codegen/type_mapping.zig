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
const ExtensionApiJson = @import("../model/ExtensionApiJson.zig");
