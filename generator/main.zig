//! Thin command dispatcher for the generator tool.
//!
//! All semantic work lives in the backend modules. This file only selects a
//! backend and forwards the remaining command-line arguments.

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2 or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        try writeUsage();
        if (args.len < 2) return error.MissingSubcommand;
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "bindgen")) {
        return bindgen.run(arena, init.io, args[2..]);
    }
    if (std.mem.eql(u8, command, "codegen")) {
        return codegen.run(arena, init.io, args[2..]);
    }

    std.log.err("Unknown generator subcommand: {s}", .{command});
    try writeUsage();
    return error.UnknownSubcommand;
}

fn writeUsage() !void {
    std.debug.print(
        \\Usage:
        \\  generator bindgen --interface-json=<path> --extension-api-json=<path> --output-dir=<path>
        \\  generator codegen --extension-api-json=<path> --out-dir=<path>
        \\
        \\Shared options:
        \\  --builtin-build-conf <float_32|float_64|double_32|double_64>
        \\  --member-initialization <none|undefined|zero>
        \\  --strip-deprecation <true|false>
        \\
    , .{});
}

const std = @import("std");

const bindgen = @import("bindgen/run.zig");
const codegen = @import("codegen/run.zig");
