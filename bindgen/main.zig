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

    try generators.generateInterfaceBindings(&context, options);
}

const std = @import("std");

const Options = @import("Options.zig");
const Context = @import("Context.zig");
const generators = @import("generators.zig");
