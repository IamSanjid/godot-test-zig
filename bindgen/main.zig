pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = try Options.parseFromArgs(args);
    std.debug.print("Parsed options: {f}\n", .{options});

    var context = try Context.init(arena, init.io, options);
    defer context.deinit();

    std.debug.print("Parsed interface JSON: types: {}, interface: {}\n", .{
        context.interface_json.types.len,
        context.interface_json.interface.len,
    });
    std.debug.print("Parsed extension API JSON: builtin classes: {}, sizes configs: {}, offset configs: {}\n", .{
        context.extension_api_json.builtin_classes.len,
        context.extension_api_json.builtin_class_sizes.len,
        context.extension_api_json.builtin_class_member_offsets.len,
    });

    try generators.generateInterfaceBindings(&context, options);
}

const std = @import("std");

const Options = @import("Options.zig");
const Context = @import("Context.zig");
const generators = @import("generators.zig");
