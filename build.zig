const std = @import("std");
const build_zon = @import("build.zig.zon");
const Translator = @import("translate_c").Translator;

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
    const gd_ext_default_init = b.option(
        bool,
        "gd_ext_default_init",
        "Default initialization all the GDExtension C structs to zero or not.",
    ) orelse true;
    const gdextension_interface_header = b.option(
        std.Build.LazyPath,
        "gdextension_interface_header",
        "Path to the GDExtension interface header file.",
    ) orelse b.path("gd_interface/gdextension_interface.h");
    const gdextension_interface_json = b.option(
        []const u8,
        "gdextension_interface_json",
        "Path to the GDExtension interface json file.",
    ) orelse "gd_interface/gdextension_interface.json";
    const gdextension_output_dir = b.option(
        []const u8,
        "gdextension_output_dir",
        "Path to the output directory for generated files.",
    ) orelse "src/godot";

    const translate_c = b.dependency("translate_c", .{});
    const godot_interface: Translator = .init(translate_c, .{
        .c_source_file = gdextension_interface_header,
        .target = target,
        .optimize = optimize,
        .default_init = gd_ext_default_init,
    });

    const bindgen = b.addExecutable(.{
        .name = "bindgen",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("bindgen/main.zig"),
        }),
    });
    const bindgen_step = b.step("gen", "Generate godot bindgen");
    const bindgen_run = b.addRunArtifact(bindgen);
    bindgen_run.expectExitCode(0);
    bindgen_run.addArg(b.fmt("--interface_json={s}", .{gdextension_interface_json}));
    bindgen_run.addArg(b.fmt("--output_dir={s}", .{gdextension_output_dir}));
    bindgen_run.setCwd(b.path("."));
    bindgen_step.dependOn(&bindgen_run.step);

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
