pub const InitializationLevel = enum(u32) {
    core = 0,
    servers = 1,
    scene = 2,
    editor = 3,
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const minimum_initialization_level: InitializationLevel = b.option(
        InitializationLevel,
        "minimum_initialization_level",
        "Minimum initialization level for the library",
    ) orelse .scene;
    const install_dir = b.option(
        []const u8,
        "install_dir",
        "Install directory for the dynamic library, relative to the install prefix (zig-out by default).",
    ) orelse "../../lib";
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
    const gdext_extension_api_json = b.option(
        []const u8,
        "gdext_extension_api_json",
        "Path to the Godot extension_api.json file.",
    ) orelse "gd_interface/extension_api.json";
    const default_builtin_build_conf: generator.BuiltinBuildConf = if (target.result.ptrBitWidth() == 32)
        .float_32
    else
        .float_64;
    const gdext_builtin_build_conf = b.option(
        generator.BuiltinBuildConf,
        "gdext_builtin_build_conf",
        "Builtin class layout build configuration; defaults from the target pointer width.",
    ) orelse default_builtin_build_conf;
    const gdext_bindgen_output_dir = b.option(
        []const u8,
        "gdext_bindgen_output_dir",
        "Bindgen output directory; must contain the hand-written bindings.zig module root.",
    ) orelse "src/godot/bindings";
    const gdext_codegen_output_dir = b.option(
        []const u8,
        "gdext_codegen_output_dir",
        "Root directory of the generated codegen layer; must contain runtime.zig, godot.zig, naming.zig, and tests.zig.",
    ) orelse "src/godot";
    const gdext_interface_import = b.option(
        []const u8,
        "gdext_interface_import",
        "Module name generated bindings import for the GDExtension interface.",
    ) orelse "godot_interface";
    const gdext_member_init = b.option(
        generator.MemberInitialization,
        "gdext_member_init",
        "Member initialization for generated interface and builtin extern structs.",
    ) orelse .zero;
    const gdext_strip_deprecation = b.option(
        bool,
        "gdext_strip_deprecation",
        "Strip deprecated interface and API members from generated output.",
    ) orelse false;

    // translate-c runs on the build host; the generated module is still
    // configured for the requested target by Translator.init.
    const translate_c = b.dependency("translate_c", .{ .target = b.graph.host });
    const godot_interface: Translator = .init(translate_c, .{
        .c_source_file = gdext_interface_header,
        .target = target,
        .optimize = optimize,
        .default_init = gdext_member_init != .none,
    });

    const layer_root = gdext_codegen_output_dir;
    const bindings_root = b.fmt("{s}/bindings.zig", .{gdext_bindgen_output_dir});
    const naming_root = b.fmt("{s}/naming.zig", .{layer_root});

    const casez = b.dependency("casez", .{}).module("casez");
    const naming = b.createModule(.{
        .root_source_file = b.path(naming_root),
        .imports = &.{
            .{ .name = "casez", .module = casez },
        },
    });

    const generator_executable = generator.buildGenerator(b, naming);

    const api_opts: generator.ApiOptions = .{
        .extension_api_json = gdext_extension_api_json,
        .builtin_build_conf = gdext_builtin_build_conf,
        .member_initialization = gdext_member_init,
        .strip_deprecation = gdext_strip_deprecation,
    };

    const bindgen_opt: generator.RunBindgenOptions = .{
        .api = api_opts,
        .generator = generator_executable,
        .interface_json = gdext_interface_json,
        .output_dir = gdext_bindgen_output_dir,
        .interface_import = gdext_interface_import,
    };
    const run_bindgen = generator.runBindgen(b, bindgen_opt);
    const bindgen_step = b.step("bindgen", "Generate godot bindings");
    bindgen_step.dependOn(&run_bindgen.step);

    const codegen_opt: generator.RunCodegenOptions = .{
        .api = api_opts,
        .generator = generator_executable,
        .output_dir = gdext_codegen_output_dir,
    };
    const run_codegen = generator.runCodegen(b, codegen_opt);
    run_codegen.step.dependOn(&run_bindgen.step);
    const codegen_step = b.step("codegen", "Generate the automatic-dispatch codegen layer");
    codegen_step.dependOn(&run_codegen.step);

    const gen_step = b.step("gen", "Generate bindings, codegen, and the scanned class namespace");
    gen_step.dependOn(&run_codegen.step);

    const test_run = generator.buildAndRunTests(b, .{ .naming = naming });
    const test_generator_step = b.step("test-generator", "Run all generator unit tests");
    test_generator_step.dependOn(&test_run.step);

    const build_options = b.addOptions();
    build_options.addOption(InitializationLevel, "minimum_initialization_level", minimum_initialization_level);
    const build_options_module = build_options.createModule();

    const bindings = b.createModule(.{
        .root_source_file = b.path(bindings_root),
        .imports = &.{
            .{ .name = gdext_interface_import, .module = godot_interface.mod },
        },
        .target = target,
        .optimize = optimize,
    });

    const godot = b.createModule(.{
        .root_source_file = b.path(b.fmt("{s}/godot.zig", .{layer_root})),
        .imports = &.{
            .{ .name = "build_options", .module = build_options_module },
            .{ .name = "bindings", .module = bindings },
            .{ .name = "naming", .module = naming },
        },
        .target = target,
        .optimize = optimize,
    });

    const godot_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("{s}/tests.zig", .{layer_root})),
            .imports = &.{
                .{ .name = "build_options", .module = build_options_module },
                .{ .name = "bindings", .module = bindings },
                .{ .name = "naming", .module = naming },
            },
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_godot_tests = b.addRunArtifact(godot_tests);
    // Cross-target test binaries cannot always run on the host; still compile
    // and semantically analyze them for the requested target.
    run_godot_tests.skip_foreign_checks = true;
    godot_tests.step.dependOn(&run_codegen.step);
    run_godot_tests.step.dependOn(&run_codegen.step);
    const test_godot_step = b.step("test-godot", "Run runtime tests and analyze generated bindings/codegen");
    test_godot_step.dependOn(&run_godot_tests.step);

    const test_step = b.step("test", "Run generator and runtime tests");
    test_step.dependOn(test_generator_step);
    test_step.dependOn(test_godot_step);

    const lib = b.addLibrary(.{
        .name = @tagName(build_zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/entrypoint.zig"),
            .imports = &.{
                .{ .name = "godot", .module = godot },
                // Opt-in raw ABI layer for bindings-only entry points.
                // .{ .name = "bindings", .module = bindings },
            },
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = install_dir } },
        .pdb_dir = if (target.result.os.tag == .windows)
            .{ .override = .{ .custom = install_dir } }
        else
            .disabled,
    });
    b.getInstallStep().dependOn(&install.step);

    const scan = b.step("scan", "Generate the extension class namespace module.");
    scan.dependOn(&class_files.scanAndGenerate(b, "src", .{
        .generated_module_path = "src/example.gen.zig",
        .ignore = &.{ "godot/**", "**/*.gen.zig" },
    }).step);
    // Example scaffold: remove this wiring with src/example/ and src/example.gen.zig.
    // `zig build gen` writes generated sources; `test-godot` regenerates first.
    gen_step.dependOn(scan);
}

const std = @import("std");
const build_zon = @import("build.zig.zon");
const Translator = @import("translate_c").Translator;

const generator = @import("build/generator.zig");
const class_files = @import("build/class_files.zig");
