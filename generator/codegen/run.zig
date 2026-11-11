//! Codegen backend entry point.
//!
//! The renderers are intentionally independent: each consumes the shared API
//! model and resolver and owns only its part of the output tree.

pub fn run(arena: Allocator, io: Io, args: []const [:0]const u8) !void {
    const options = try Options.parseFromArgs(args);
    std.debug.print("Parsed options: {f}\n", .{options});

    const api = try readExtensionApi(arena, io, options.api.extension_api_json);
    std.debug.print("Parsed extension API JSON: builtin classes: {}, classes: {}, singletons: {}, native: {}, global constants: {}, global enums: {}\n", .{
        api.builtin_classes.len,
        api.classes.len,
        api.singletons.len,
        api.native_structures.len,
        api.global_constants.len,
        api.global_enums.len,
    });

    Io.Dir.cwd().createDirPath(io, options.output_dir) catch |err| {
        std.log.err("Failed to create codegen output directory `{s}`: {}", .{ options.output_dir, err });
        return err;
    };

    try custom_code.warnUnsupportedArtifacts(arena, io);

    const builtin_names = try collectBuiltinNames(arena, api);
    const real_name = types.realTypeName(options.api.builtin_build_conf);
    const resolver = try ClassResolver.init(arena, api, real_name, builtin_names);
    const templates = try template_mod.Set.load(arena, io);

    try artifacts.generateGlobals(arena, io, api, options);
    try artifacts.generateNative(arena, io, api, options);
    try artifacts.generateSingletons(arena, io, api, options, &resolver);

    try class_gen.generate(arena, io, api, options, &resolver, &templates);
    try builtin.generate(arena, io, api, options, &resolver, &templates);
    try utility.generate(arena, io, api, options, &resolver);
}

fn readExtensionApi(arena: Allocator, io: Io, path: []const u8) !ExtensionApiJson {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| {
        std.log.err("Failed to read extension API JSON `{s}`: {}", .{ path, err });
        return err;
    };
    const json_bytes = if (std.mem.startsWith(u8, bytes, "\xEF\xBB\xBF")) bytes[3..] else bytes;
    return (try ExtensionApiJson.parse(arena, json_bytes)).value;
}

fn collectBuiltinNames(arena: Allocator, api: ExtensionApiJson) ![]const []const u8 {
    const result = try arena.alloc([]const u8, api.builtin_classes.len);
    var count: usize = 0;
    for (api.builtin_classes) |class| {
        if (isPrimitive(class.name)) continue;
        result[count] = class.name;
        count += 1;
    }
    return result[0..count];
}

fn isPrimitive(name: []const u8) bool {
    return std.mem.eql(u8, name, "Nil") or
        std.mem.eql(u8, name, "bool") or
        std.mem.eql(u8, name, "int") or
        std.mem.eql(u8, name, "float");
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const artifacts = @import("artifacts.zig");
const builtin = @import("builtin.zig");
const class_gen = @import("class.zig");
const custom_code = @import("custom.zig");
const template_mod = @import("templates.zig");
const utility = @import("utility.zig");
const types = @import("../model/types.zig");
const ExtensionApiJson = @import("../model/ExtensionApiJson.zig");
const ClassResolver = @import("../model/resolver.zig").ClassResolver;
const Options = @import("Options.zig");
