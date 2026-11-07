arena: Allocator,
io: Io,
interface_json: []const u8, // content

const Context = @This();

pub fn init(arena: Allocator, io: Io, options: Options) !Context {
    const interface_json = Io.Dir.cwd().readFileAlloc(io, options.interface_json, arena, .unlimited) catch |err| {
        std.log.err("Failed to read interface json file: {}", .{err});
        return err;
    };

    return Context{
        .arena = arena,
        .io = io,
        .interface_json = interface_json,
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Options = @import("Options.zig");
