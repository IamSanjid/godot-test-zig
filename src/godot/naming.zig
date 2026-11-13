//! Shared Godot/Zig naming policy.
//!
//! `zig` is the spelling used for generated Zig identifiers and file names.
//! `godot` is for engine-facing reflection names. Godot type names are preserved
//! by generated `GodotClassName` declarations; Pascal conversion is only the
//! fallback for types that do not provide one.

/// Godot naming. Use this for reflection and engine-facing strings.
/// Godot enum values are engine constants and therefore ALL_CAPS.
pub const godot = struct {
    pub const constant = casez.Config.constant;
    pub const enum_variant = casez.Config.constant;
    pub const file = casez.Config.snake;
    pub const func = casez.Config.snake;
    pub const method = casez.Config.snake;
    pub const property = casez.Config.snake;
    pub const signal = casez.Config.snake;
    pub const virtual_method = casez.Config.with(.snake, .{
        .prefix = "_",
    });
    pub const @"type" = casez.Config.pascal;
};

/// Zig naming. This must preserve the existing bindgen/codegen output.
pub const zig = struct {
    pub const argument = casez.Config.snake;
    pub const constant = casez.Config.snake;
    pub const enum_variant = casez.Config.snake;
    pub const field = casez.Config.snake;
    pub const file = casez.Config.snake;
    pub const func = casez.Config.camel;
    pub const method = casez.Config.camel;
    pub const property = casez.Config.snake;
    pub const signal = casez.Config.pascal;
    pub const @"type" = casez.Config.pascal;
    pub const virtual_method = casez.Config.with(.camel, .{
        .prefix = "_",
    });
};

pub const Case = enum { godot, zig };

pub inline fn comptimeConvert(
    comptime case: Case,
    comptime @"for": @EnumLiteral(),
    comptime input: []const u8,
) ComptimeConvertType(case, @"for", input) {
    return casez.comptimeConvert(@field(CaseConfig(case), @tagName(@"for")), input);
}

fn ComptimeConvertType(
    comptime case: Case,
    comptime @"for": @EnumLiteral(),
    comptime input: []const u8,
) type {
    return @TypeOf(casez.comptimeConvert(@field(CaseConfig(case), @tagName(@"for")), input));
}

pub inline fn allocConvert(
    comptime case: Case,
    comptime @"for": @EnumLiteral(),
    allocator: std.mem.Allocator,
    input: []const u8,
) ![]const u8 {
    return casez.allocConvert(allocator, @field(CaseConfig(case), @tagName(@"for")), input);
}

pub inline fn writeConvert(
    writer: *std.Io.Writer,
    comptime case: Case,
    comptime @"for": @EnumLiteral(),
    input: []const u8,
) !void {
    try casez.writeConvert(writer, @field(CaseConfig(case), @tagName(@"for")), input);
}

fn CaseConfig(comptime case: Case) type {
    return switch (case) {
        .godot => godot,
        .zig => zig,
    };
}

const std = @import("std");

const casez = @import("casez");
