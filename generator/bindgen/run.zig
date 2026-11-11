//! Bindgen backend entry point. `generator/main.zig` dispatches here after the
//! `bindgen` subcommand.

pub fn run(arena: Allocator, io: Io, args: []const [:0]const u8) !void {
    const options = try Options.parseFromArgs(args);
    std.debug.print("Parsed options: {f}\n", .{options});

    var context = try Context.init(arena, io, options);
    defer context.deinit();

    std.debug.print("Parsed interface JSON: types: {}, interface: {}\n", .{
        context.interface_json.types.len,
        context.interface_json.interface.len,
    });
    std.debug.print("Parsed extension API JSON: builtin classes: {}, classes: {}, singletons: {}, native: {}, utility: {}, sizes configs: {}, offset configs: {}, constants: {}, enums: {}\n", .{
        context.extension_api_json.builtin_classes.len,
        context.extension_api_json.classes.len,
        context.extension_api_json.singletons.len,
        context.extension_api_json.native_structures.len,
        context.extension_api_json.utility_functions.len,
        context.extension_api_json.builtin_class_sizes.len,
        context.extension_api_json.builtin_class_member_offsets.len,
        context.extension_api_json.global_constants.len,
        context.extension_api_json.global_enums.len,
    });

    try generators.generateInterfaceBindings(&context, options);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Options = @import("Options.zig");
const Context = @import("Context.zig");
const generators = @import("generators.zig");
