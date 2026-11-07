pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = try Options.parseFromArgs(args);
    std.debug.print("Parsed options: {f}\n", .{options});

    const context = try Context.init(arena, init.io, options);
    const size: f32 = @floatFromInt(context.interface_json.len);
    std.debug.print("Context initialized with interface_json length: {} KB.\n", .{size / 1024.0});

    const interface_json_parsed = try InterfaceJson.parse(arena, context.interface_json);
    std.debug.print("Parsed interface JSON: types: {}, interface: {}\n", .{ interface_json_parsed.value.types.len, interface_json_parsed.value.interface.len });
}

const std = @import("std");

const Options = @import("Options.zig");
const Context = @import("Context.zig");
const InterfaceJson = @import("InterfaceJson.zig");
