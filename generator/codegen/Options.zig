//! Options for the automatic-dispatch codegen backend.

api: api_options.ApiOptions,
output_dir: []const u8,
/// Module name of the raw bindings root.
bindings_module: []const u8 = "bindings",

pub const CodegenOptions = @This();

pub const ApiOptions = api_options.ApiOptions;
pub const BuiltinBuildConf = api_options.BuiltinBuildConf;
pub const MemberInitialization = api_options.MemberInitialization;

pub fn parseFromArgs(args: []const [:0]const u8) !CodegenOptions {
    return .{
        .api = try ApiOptions.parseFromArgs(args),
        .output_dir = try cli.requiredAny(args, &.{ "--output-dir", "--output_dir", "--out-dir", "--out_dir" }),
        .bindings_module = try cli.parseOptional(
            []const u8,
            args,
            &.{ "--bindings-module", "--bindings_module" },
            "bindings",
        ),
    };
}

pub fn format(self: CodegenOptions, writer: *Io.Writer) void {
    writer.print("Options:\n", .{}) catch {};
    writer.print("  --extension-api-json={s}\n", .{self.api.extension_api_json}) catch {};
    writer.print("  --output-dir={s}\n", .{self.output_dir}) catch {};
    writer.print("  --bindings-module={s}\n", .{self.bindings_module}) catch {};
    writer.print("  --builtin-build-conf={s}\n", .{@tagName(self.api.builtin_build_conf)}) catch {};
    writer.print("  --member-initialization={s}\n", .{@tagName(self.api.member_initialization)}) catch {};
    writer.print("  --strip-deprecation={}\n", .{self.api.strip_deprecation}) catch {};
}

test "codegen options parse the canonical invocation" {
    const options = try CodegenOptions.parseFromArgs(&.{
        "--extension-api-json=extension_api.json",
        "--out-dir=auto",
        "--bindings-module=bindings",
    });
    try std.testing.expectEqualStrings("auto", options.output_dir);
    try std.testing.expectEqualStrings("bindings", options.bindings_module);
}

test "codegen options default module names" {
    const options = try CodegenOptions.parseFromArgs(&.{
        "--extension-api-json=extension_api.json",
        "--output-dir=auto",
    });
    try std.testing.expectEqualStrings("bindings", options.bindings_module);
}

const std = @import("std");
const Io = std.Io;

const api_options = @import("../model/api_options.zig");
const cli = @import("../model/cli.zig");
