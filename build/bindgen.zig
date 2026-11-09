pub const RunOptions = struct {
    interface_json: []const u8 = "",
    output_dir: []const u8 = "",
    member_initialization: MemberInitialization = .none,
    strip_deprecation: bool = false,
    run_step_name: []const u8 = "gen",
    casez: *std.Build.Module,
};

pub const TestOptions = struct {
    test_step_name: []const u8 = "test-bindgen",
    casez: *std.Build.Module,
};

pub fn buildRun(b: *std.Build, opt: RunOptions) void {
    const bindgen = b.addExecutable(.{
        .name = "bindgen",
        .root_module = b.createModule(.{
            .optimize = .debug,
            .target = b.graph.host, // use host to run the bindgen.
            .root_source_file = b.path("bindgen/main.zig"),
            .imports = &.{
                .{ .name = "casez", .module = opt.casez },
            },
        }),
    });

    const bindgen_run = b.addRunArtifact(bindgen);
    bindgen_run.expectExitCode(0);
    bindgen_run.addArg(b.fmt("--interface_json={s}", .{opt.interface_json}));
    bindgen_run.addArg(b.fmt("--output_dir={s}", .{opt.output_dir}));
    bindgen_run.addArg(b.fmt("--member_initialization={s}", .{@tagName(opt.member_initialization)}));
    bindgen_run.addArg(b.fmt("--strip_deprecation={}", .{opt.strip_deprecation}));
    bindgen_run.setCwd(b.path("."));
    bindgen_run.addPassthruArgs();

    const bindgen_step = b.step(opt.run_step_name, "Generate godot bindgen");
    bindgen_step.dependOn(&bindgen_run.step);
}

pub fn buildTest(b: *std.Build, opt: TestOptions) void {
    const bindgen_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .optimize = .debug,
            .target = b.graph.host,
            .root_source_file = b.path("bindgen/tests.zig"),
            .imports = &.{
                .{ .name = "casez", .module = opt.casez },
            },
        }),
    });

    const bindgen_test_step = b.step(opt.test_step_name, "Run bindgen unit tests");
    bindgen_test_step.dependOn(&b.addRunArtifact(bindgen_tests).step);
}

const std = @import("std");

pub const MemberInitialization = @import("../bindgen/Options.zig").MemberInitialization;
