pub const InitializationLevel = enum(u32) {
    core = 0,
    servers = 1,
    scene = 2,
    editor = 3,
};

pub fn build(b: *std.Build) !void {
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
        bindgen.BuiltinBuildConf,
        "gdext_builtin_build_conf",
        "Builtin class layout build configuration.",
    ) orelse .float_64;
    const gdext_bindgen_output_dir = b.option(
        []const u8,
        "gdext_bindgen_output_dir",
        "Path to the output directory for generated files.",
    ) orelse "src/godot/bindings";
    const gdext_interface_import = b.option(
        []const u8,
        "gdext_interface_import",
        "This will be used for the godot interface module name when imported by the bindings.",
    ) orelse "godot_interface";
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

    bindgen.buildRun(b, .{
        .interface_json = gdext_interface_json,
        .extension_api_json = gdext_extension_api_json,
        .output_dir = gdext_bindgen_output_dir,
        .interface_import = gdext_interface_import,
        .member_initialization = gdext_member_init,
        .builtin_build_conf = gdext_builtin_build_conf,
        .strip_deprecation = gdext_strip_deprecation,
        .casez = casez,
    });
    bindgen.buildTest(b, .{ .casez = casez });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "entry_point", entry_point);
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

    const lib = b.addLibrary(.{
        .name = @tagName(build_zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/entrypoint.zig"),
            .imports = &.{
                .{ .name = "build_options", .module = build_options.createModule() },
                .{ .name = "bindings", .module = bindings },
            },
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = install_dir } },
        .pdb_dir = .{ .override = .{ .custom = install_dir } },
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

const bindgen = @import("build/bindgen.zig");
const MemberInitialization = bindgen.MemberInitialization;
