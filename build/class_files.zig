//! Build helpers for generated class-file namespaces.

/// Options for one class-file scan step. The generated module contains
/// file-stem aliases for matching files; keep the output out of hand edits.
pub const ScanOptions = struct {
    /// Generated module path, relative to the build root.
    generated_module_path: []const u8,
    /// Optimization mode for the scanner executable.
    optimize: std.lang.OptimizeMode = .fast,
    /// Gitignore-style rules, relative to `sub_path`; replaces the default.
    /// Generated codegen classes also declare `Extends`, so exclude the
    /// runtime layer when scanning the whole `src` tree.
    ignore: []const []const u8 = &.{"**/*.gen.zig"},
};

/// Adds a build step that scans `sub_path` and writes `generated_module_path`.
pub fn scanAndGenerate(b: *Build, sub_path: []const u8, options: ScanOptions) *Build.Step.Run {
    const zlob = b.dependency("zlob", .{
        .target = b.graph.host,
        .optimize = .fast, // zlob needs to be as fast as possible
        .@"static-only" = true,
    }).module("zlob");

    const class_files_scan_and_gen = b.addExecutable(.{
        .name = "class_files_scan_and_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/tools/class_files_scan_and_gen.zig"),
            .target = b.graph.host,
            .optimize = options.optimize,
            .imports = &.{
                .{ .name = "zlob", .module = zlob },
            },
        }),
    });

    const run = b.addRunArtifact(class_files_scan_and_gen);
    run.has_side_effects = true;
    run.stdio = .inherit;
    run.setCwd(b.path("."));
    run.addDirectoryArg2(std.Build.LazyPath.cache_root, .{ .make_absolute = true });
    run.addDirectoryArg2(b.path(sub_path), .{ .make_absolute = true });
    // The scanner writes this path; the absolute file arg keeps path
    // construction out of the tool.
    run.addFileArg2(b.path(options.generated_module_path), .{ .make_absolute = true });
    run.addArgs(options.ignore);

    return run;
}

const std = @import("std");
const Build = std.Build;
