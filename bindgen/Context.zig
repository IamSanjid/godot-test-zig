arena: Allocator,
io: Io,
interface_json: InterfaceJson, // content
extension_api_json: ExtensionApiJson,
interface_wrapper: Io.File,

const Context = @This();

pub fn init(arena: Allocator, io: Io, options: Options) !Context {
    const interface_json_bytes = Io.Dir.cwd().readFileAlloc(io, options.interface_json, arena, .unlimited) catch |err| {
        std.log.err("Failed to read interface json file: {}", .{err});
        return err;
    };
    // Be liberal about the UTF-8 BOM that some editors prepend; std.json does
    // not accept it.
    const json_bytes = if (std.mem.startsWith(u8, interface_json_bytes, "\xEF\xBB\xBF"))
        interface_json_bytes[3..]
    else
        interface_json_bytes;
    const interface_json_parsed = try InterfaceJson.parse(arena, json_bytes);

    const extension_api_bytes = Io.Dir.cwd().readFileAlloc(io, options.extension_api_json, arena, .unlimited) catch |err| {
        std.log.err("Failed to read extension api json file: {}", .{err});
        return err;
    };
    const extension_api_json_bytes = if (std.mem.startsWith(u8, extension_api_bytes, "\xEF\xBB\xBF"))
        extension_api_bytes[3..]
    else
        extension_api_bytes;
    const extension_api_json_parsed = try ExtensionApiJson.parse(arena, extension_api_json_bytes);

    Io.Dir.cwd().createDirPath(io, options.output_dir) catch |err| {
        std.log.err("Failed to create output directory `{s}`: {}", .{ options.output_dir, err });
        return err;
    };

    const interface_wrapper_path = try std.fs.path.join(arena, &.{ options.output_dir, "interface.zig" });
    const interface_wrapper = Io.Dir.cwd().createFile(io, interface_wrapper_path, .{}) catch |err| {
        std.log.err("Failed to create interface wrapper file `{s}`: {}", .{ interface_wrapper_path, err });
        return err;
    };

    return Context{
        .arena = arena,
        .io = io,
        .interface_json = interface_json_parsed.value,
        .extension_api_json = extension_api_json_parsed.value,
        .interface_wrapper = interface_wrapper,
    };
}

pub fn deinit(self: *Context) void {
    self.interface_wrapper.close(self.io);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Options = @import("Options.zig");
const InterfaceJson = @import("InterfaceJson.zig");
const ExtensionApiJson = @import("ExtensionApiJson.zig");
