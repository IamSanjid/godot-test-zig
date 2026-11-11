//! Options for the raw binding generator backend.

api: api_options.ApiOptions,
interface_json: []const u8,
output_dir: []const u8,
/// Module name used by the generated interface wrapper for the translated C
/// GDExtension interface.
interface_import: []const u8 = "godot_interface",

pub const BindgenOptions = @This();

pub const ApiOptions = api_options.ApiOptions;
pub const BuiltinBuildConf = api_options.BuiltinBuildConf;
pub const MemberInitialization = api_options.MemberInitialization;

pub fn parseFromArgs(args: []const [:0]const u8) !BindgenOptions {
    return .{
        .api = try ApiOptions.parseFromArgs(args),
        .interface_json = try cli.requiredAny(args, &.{ "--interface-json", "--interface_json" }),
        .output_dir = try cli.requiredAny(args, &.{ "--output-dir", "--output_dir" }),
        .interface_import = try cli.parseOptional(
            []const u8,
            args,
            &.{ "--interface-import", "--interface_import" },
            "godot_interface",
        ),
    };
}

pub fn format(self: BindgenOptions, writer: *Io.Writer) void {
    writer.print("Options:\n", .{}) catch {};
    writer.print("  --interface-json={s}\n", .{self.interface_json}) catch {};
    writer.print("  --extension-api-json={s}\n", .{self.api.extension_api_json}) catch {};
    writer.print("  --output-dir={s}\n", .{self.output_dir}) catch {};
    writer.print("  --builtin-build-conf={s}\n", .{@tagName(self.api.builtin_build_conf)}) catch {};
    writer.print("  --interface-import={s}\n", .{self.interface_import}) catch {};
    writer.print("  --member-initialization={s}\n", .{@tagName(self.api.member_initialization)}) catch {};
    writer.print("  --strip-deprecation={}\n", .{self.api.strip_deprecation}) catch {};
}

test "bindgen options parse a complete invocation" {
    const options = try BindgenOptions.parseFromArgs(&.{
        "--interface-json=in.json",
        "--extension-api-json=extension_api.json",
        "--output-dir=out",
        "--builtin-build-conf=double_32",
        "--member-initialization=zero",
        "--strip-deprecation=true",
    });
    try std.testing.expectEqualStrings("in.json", options.interface_json);
    try std.testing.expectEqualStrings("extension_api.json", options.api.extension_api_json);
    try std.testing.expectEqualStrings("out", options.output_dir);
    try std.testing.expectEqual(MemberInitialization.zero, options.api.member_initialization);
    try std.testing.expectEqual(BuiltinBuildConf.double_32, options.api.builtin_build_conf);
    try std.testing.expect(options.api.strip_deprecation);
}

test "bindgen options defaults and legacy underscores" {
    const options = try BindgenOptions.parseFromArgs(&.{
        "--interface_json=in.json",
        "--extension_api_json=extension_api.json",
        "--output_dir=out",
    });
    try std.testing.expectEqualStrings("godot_interface", options.interface_import);
    try std.testing.expectEqual(MemberInitialization.none, options.api.member_initialization);
    try std.testing.expectEqual(BuiltinBuildConf.float_64, options.api.builtin_build_conf);
}

test "bindgen option formatting uses canonical kebab-case" {
    const options = try BindgenOptions.parseFromArgs(&.{
        "--interface-json=in.json",
        "--extension-api-json=extension_api.json",
        "--output-dir=out",
    });
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    options.format(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "--output-dir=out") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "--member-initialization=none") != null);
}

const std = @import("std");
const Io = std.Io;

const api_options = @import("../model/api_options.zig");
const cli = @import("../model/cli.zig");
