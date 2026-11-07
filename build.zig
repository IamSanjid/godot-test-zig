pub const InitializationLevel = enum {
    core,
    servers,
    scene,
    editor,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const entry_point = b.option(
        []const u8,
        "entry_point",
        "Entry point for the library",
    ) orelse (@tagName(build_zon.name) ++ "_gd_ext_init");
    const minimum_initialization_level: InitializationLevel = b.option(
        InitializationLevel,
        "minimum_initialization_level",
        "Minimum initialization level for the library",
    ) orelse .scene;
    const gdext_interface_header = b.option(
        std.Build.LazyPath,
        "gdext_interface_header",
        "Path to the GDExtension interface header file.",
    ) orelse b.path("gd_interface/gdextension_interface.h");
    const gdext_interface_json = b.option(
        []const u8,
        "gdext_interface_json",
        "Path to the GDExtension interface json file.",
    ) orelse "gd_interface/gdextension_interface.json";
    const gdext_output_dir = b.option(
        []const u8,
        "gdextension_output_dir",
        "Path to the output directory for generated files.",
    ) orelse "src/godot/bindings";
    const gdext_member_init = b.option(
        MemberInitialization,
        "gdext_member_init",
        "Member initialization for gdextension interface extern structs.",
    ) orelse .zero;
    const gdext_strip_deprecation = b.option(
        bool,
        "gdext_strip_deprecation",
        "Stip all the deprecated extension interface.",
    ) orelse false;

    const translate_c = b.dependency("translate_c", .{});
    const godot_interface: Translator = .init(translate_c, .{
        .c_source_file = gdext_interface_header,
        .target = target,
        .optimize = optimize,
        .default_init = gdext_member_init != .none,
    });

    const casez = b.dependency("casez", .{}).module("casez");

    const bindgen_module = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("bindgen/main.zig"),
        .imports = &.{
            .{ .name = "casez", .module = casez },
        },
    });
    const bindgen = b.addExecutable(.{
        .name = "bindgen",
        .root_module = bindgen_module,
    });
    const bindgen_step = b.step("gen", "Generate godot bindgen");
    const bindgen_run = b.addRunArtifact(bindgen);
    bindgen_run.expectExitCode(0);
    bindgen_run.addArg(b.fmt("--interface_json={s}", .{gdext_interface_json}));
    bindgen_run.addArg(b.fmt("--output_dir={s}", .{gdext_output_dir}));
    bindgen_run.addArg(b.fmt("--member_initialization={s}", .{@tagName(gdext_member_init)}));
    bindgen_run.addArg(b.fmt("--strip_deprecation={}", .{gdext_strip_deprecation}));
    bindgen_run.setCwd(b.path("."));
    bindgen_run.addPassthruArgs();
    bindgen_step.dependOn(&bindgen_run.step);

    const bindgen_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("bindgen/tests.zig"),
            .imports = &.{
                .{ .name = "casez", .module = casez },
            },
        }),
    });
    const bindgen_test_step = b.step("test-bindgen", "Run bindgen unit tests");
    bindgen_test_step.dependOn(&b.addRunArtifact(bindgen_tests).step);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "entry_point", entry_point);
    build_options.addOption(InitializationLevel, "minimum_initialization_level", minimum_initialization_level);

    const test_zig = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = build_options.createModule() },
            .{ .name = "godot_interface", .module = godot_interface.mod },
        },
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "test_zig",
        .root_module = test_zig,
        .linkage = .dynamic,
    });
    const install = b.addInstallFileWithDir(
        lib.getEmittedBin(),
        .{ .custom = "../../lib" },
        lib.out_filename,
    );
    b.default_step.dependOn(&install.step);
}

const std = @import("std");
const build_zon = @import("build.zig.zon");
const Translator = @import("translate_c").Translator;

const MemberInitialization = @import("bindgen/Options.zig").MemberInitialization;
