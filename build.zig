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
        "Install directory for the dynamic libs to get installed. Can be relative to current project directory.",
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
    const gdext_builtin_build_conf = b.option(
        generator.BuiltinBuildConf,
        "gdext_builtin_build_conf",
        "Builtin class layout build configuration.",
    ) orelse .float_64;
    const gdext_bindgen_output_dir = b.option(
        []const u8,
        "gdext_bindgen_output_dir",
        "Path to the output directory for generated bindings.",
    ) orelse "src/godot/bindings";
    const gdext_codegen_output_dir = b.option(
        []const u8,
        "gdext_codegen_output_dir",
        "Path to the output directory for the codegen layer.",
    ) orelse "src/godot";
    const gdext_interface_import = b.option(
        []const u8,
        "gdext_interface_import",
        "This will be used for the godot interface module name when imported by the bindings.",
    ) orelse "godot_interface";
    const gdext_member_init = b.option(
        generator.MemberInitialization,
        "gdext_member_init",
        "Member initialization for gdextension interface extern structs.",
    ) orelse .zero;
    const gdext_strip_deprecation = b.option(
        bool,
        "gdext_strip_deprecation",
        "Stip all the deprecated extension interface.",
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

    const casez = b.dependency("casez", .{}).module("casez");
    const generator_executable = generator.buildGenerator(b, casez);

    const bindgen_opt: generator.RunBindgenOptions = .{
        .api = .{
            .extension_api_json = gdext_extension_api_json,
            .builtin_build_conf = gdext_builtin_build_conf,
            .member_initialization = gdext_member_init,
            .strip_deprecation = gdext_strip_deprecation,
        },
        .generator = generator_executable,
        .interface_json = gdext_interface_json,
        .output_dir = gdext_bindgen_output_dir,
        .interface_import = gdext_interface_import,
    };
    const run_bindgen = generator.runBindgen(b, bindgen_opt);
    const bindgen_step = b.step("bindgen", "Generate godot bindings");
    bindgen_step.dependOn(&run_bindgen.step);

    const codegen_opt: generator.RunCodegenOptions = .{
        .api = .{
            .extension_api_json = gdext_extension_api_json,
            .builtin_build_conf = gdext_builtin_build_conf,
            .member_initialization = gdext_member_init,
            .strip_deprecation = gdext_strip_deprecation,
        },
        .generator = generator_executable,
        .output_dir = gdext_codegen_output_dir,
    };
    const run_codegen = generator.runCodegen(b, codegen_opt);
    const codegen_step = b.step("codegen", "Generate the automatic-dispatch codegen layer");
    codegen_step.dependOn(&run_codegen.step);

    const run_all = generator.runAll(b, .{ .bindgen = bindgen_opt, .codegen = codegen_opt });
    const gen_step = b.step("gen", "Generate bindings, then the automatic-dispatch codegen layer");
    gen_step.dependOn(&run_all.step);

    const test_run = generator.buildAndRunTests(b, .{ .casez = casez });
    const test_generator_step = b.step("test-generator", "Run all generator unit tests");
    test_generator_step.dependOn(&test_run.step);

    const build_options = b.addOptions();
    build_options.addOption(InitializationLevel, "minimum_initialization_level", minimum_initialization_level);
    build_options.addOption(struct { os_tag: std.Target.Os.Tag }, "target", .{ .os_tag = target.result.os.tag });

    const bindings = b.createModule(.{
        .root_source_file = b.path("src/godot/bindings/bindings.zig"),
        .imports = &.{
            .{ .name = gdext_interface_import, .module = godot_interface.mod },
        },
        .target = target,
        .optimize = optimize,
    });

    const godot = b.createModule(.{
        .root_source_file = b.path("src/godot/godot.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = build_options.createModule() },
            .{ .name = "bindings", .module = bindings },
            .{ .name = "casez", .module = casez },
        },
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = @tagName(build_zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/entrypoint.zig"),
            .imports = &.{
                .{ .name = "godot", .module = godot },
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
}

pub fn scanClassesToRegister(b: *std.Build, sub_path: []const u8, options: AddFilesOptions) !std.ArrayList([]const u8) {
    const ast = try std.zig.Ast.parse(b.allocator, "pub const Extends = \"something\";", .{});
    const ast_gen = try std.zig.AstGen.generate(b.allocator, ast);
    const ins_len = ast_gen.instructions.len;
    for (0..ins_len) |i| {
        const ins = ast_gen.instructions.get(i);
        switch (ins.tag) {
            .extended => {
                std.log.debug("{}", .{ins.data.extended});
            },
            .declaration => {
                std.log.debug("{}", .{ins.data.declaration});
            },
            else => {},
        }
    }

    const io = b.graph.io;
    const root_dir = b.root.root_dir.handle;
    const search_dir = try root_dir.openDir(io, sub_path, .{ .iterate = true });
    const files = try findFiles(b.allocator, io, search_dir, options);
    for (files.items, 0..) |f, i| {
        std.log.debug("File[{}] = {s}", .{ i, f });
    }
    std.debug.assert(files.items.len > 0);

    return files;
}

const std = @import("std");
const build_zon = @import("build.zig.zon");
const Translator = @import("translate_c").Translator;

const ff = @import("build/find_files.zig");
const findFiles = ff.findFiles;
pub const AddFilesOptions = ff.Options;

const generator = @import("build/generator.zig");
