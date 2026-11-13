//! Build helper for the unified generator executable.

pub const ApiOptions = api_options.ApiOptions;
pub const BuiltinBuildConf = api_options.BuiltinBuildConf;
pub const MemberInitialization = api_options.MemberInitialization;

pub const RunBindgenOptions = struct {
    api: ApiOptions,
    generator: *std.Build.Step.Compile,
    interface_json: []const u8 = "",
    output_dir: []const u8 = "",
    interface_import: []const u8 = "godot_interface",
};

pub const RunCodegenOptions = struct {
    api: ApiOptions,
    generator: *std.Build.Step.Compile,
    output_dir: []const u8 = "",
    bindings_module: []const u8 = "bindings",
};

pub const RunAllOptions = struct {
    bindgen: RunBindgenOptions,
    codegen: RunCodegenOptions,
};

pub const BuildTestOptions = struct {
    naming: *std.Build.Module,
};

pub fn runBindgen(b: *std.Build, opt: RunBindgenOptions) *std.Build.Step.Run {
    const run = b.addRunArtifact(opt.generator);
    // stderr is diagnostic output from the generator, not a failure signal.
    // Inheriting stdio lets Zig check the exit code without treating stderr as
    // the failure reason.
    run.stdio = .inherit;
    run.addArg("bindgen");
    run.addArg(b.fmt("--interface-json={s}", .{opt.interface_json}));
    run.addArg(b.fmt("--extension-api-json={s}", .{opt.api.extension_api_json}));
    run.addArg(b.fmt("--output-dir={s}", .{opt.output_dir}));
    run.addArg(b.fmt("--interface-import={s}", .{opt.interface_import}));
    run.addArg(b.fmt("--member-initialization={s}", .{@tagName(opt.api.member_initialization)}));
    run.addArg(b.fmt("--builtin-build-conf={s}", .{@tagName(opt.api.builtin_build_conf)}));
    run.addArg(b.fmt("--strip-deprecation={}", .{opt.api.strip_deprecation}));
    run.setCwd(b.path("."));
    run.addPassthruArgs();

    return run;
}

pub fn runCodegen(b: *std.Build, opt: RunCodegenOptions) *std.Build.Step.Run {
    const run = b.addRunArtifact(opt.generator);
    // See runBindgen: generator diagnostics go to stderr on success.
    run.stdio = .inherit;
    run.addArg("codegen");
    run.addArg(b.fmt("--extension-api-json={s}", .{opt.api.extension_api_json}));
    run.addArg(b.fmt("--out-dir={s}", .{opt.output_dir}));
    run.addArg(b.fmt("--bindings-module={s}", .{opt.bindings_module}));
    run.addArg(b.fmt("--member-initialization={s}", .{@tagName(opt.api.member_initialization)}));
    run.addArg(b.fmt("--builtin-build-conf={s}", .{@tagName(opt.api.builtin_build_conf)}));
    run.addArg(b.fmt("--strip-deprecation={}", .{opt.api.strip_deprecation}));
    run.setCwd(b.path("."));
    run.addPassthruArgs();

    return run;
}

pub fn runAll(
    b: *std.Build,
    opt: RunAllOptions,
) *std.Build.Step.Run {
    const run_bindgen = runBindgen(b, opt.bindgen);
    const run_codegen = runCodegen(b, opt.codegen);

    run_codegen.step.dependOn(&run_bindgen.step);
    return run_codegen;
}

pub fn buildAndRunTests(
    b: *std.Build,
    opt: BuildTestOptions,
) *std.Build.Step.Run {
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .optimize = .debug,
            .target = b.graph.host,
            .root_source_file = b.path("generator/tests.zig"),
            .imports = &.{
                .{ .name = "naming", .module = opt.naming },
            },
        }),
    });

    const run = b.addRunArtifact(tests);
    return run;
}

pub fn buildGenerator(b: *std.Build, naming: *std.Build.Module) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "generator",
        .root_module = b.createModule(.{
            .optimize = .debug,
            .target = b.graph.host,
            .root_source_file = b.path("generator/main.zig"),
            .imports = &.{
                .{ .name = "naming", .module = naming },
            },
        }),
    });
}

const std = @import("std");
const api_options = @import("../generator/model/api_options.zig");
