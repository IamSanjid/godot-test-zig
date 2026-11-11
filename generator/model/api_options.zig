//! API-shaping options shared by bindgen and codegen.
//!
//! These values must match between the two generators. A mismatch changes
//! method signatures, builtin layout, or which deprecated API members exist.

pub const ApiOptions = struct {
    extension_api_json: []const u8,
    /// Builtin layout selected from `builtin_class_sizes` and
    /// `builtin_class_member_offsets`.
    builtin_build_conf: BuiltinBuildConf = .float_64,
    /// How members of generated `extern struct`s are initialized.
    member_initialization: MemberInitialization = .none,
    /// Omit deprecated types and interface functions from generated output.
    strip_deprecation: bool = false,

    pub fn parseFromArgs(args: []const [:0]const u8) !ApiOptions {
        return .{
            .extension_api_json = try cli.requiredAny(args, &.{ "--extension-api-json", "--extension_api_json" }),
            .builtin_build_conf = try cli.parseOptional(
                BuiltinBuildConf,
                args,
                &.{ "--builtin-build-conf", "--builtin_build_conf" },
                .float_64,
            ),
            .member_initialization = try cli.parseOptional(
                MemberInitialization,
                args,
                &.{ "--member-initialization", "--member_initialization" },
                .none,
            ),
            .strip_deprecation = try cli.parseOptional(
                bool,
                args,
                &.{ "--strip-deprecation", "--strip_deprecation" },
                false,
            ),
        };
    }
};

pub const BuiltinBuildConf = enum {
    float_32,
    float_64,
    double_32,
    double_64,
};

pub const MemberInitialization = enum {
    /// Do not write a default initializer.
    none,
    /// Initialize members with `= undefined`.
    undefined,
    /// Initialize members with `= @import("std").mem.zeroes(T)`.
    zero,
};

test "api options parse defaults" {
    const options = try ApiOptions.parseFromArgs(&.{
        "--extension-api-json=extension_api.json",
    });
    try std.testing.expectEqualStrings("extension_api.json", options.extension_api_json);
    try std.testing.expectEqual(BuiltinBuildConf.float_64, options.builtin_build_conf);
    try std.testing.expectEqual(MemberInitialization.none, options.member_initialization);
    try std.testing.expect(!options.strip_deprecation);
}

test "api options accept underscore aliases and enum values" {
    const options = try ApiOptions.parseFromArgs(&.{
        "--extension_api_json=extension_api.json",
        "--builtin_build_conf=double_32",
        "--member_initialization=zero",
        "--strip_deprecation=true",
    });
    try std.testing.expectEqual(BuiltinBuildConf.double_32, options.builtin_build_conf);
    try std.testing.expectEqual(MemberInitialization.zero, options.member_initialization);
    try std.testing.expect(options.strip_deprecation);
}

const std = @import("std");
const cli = @import("cli.zig");
