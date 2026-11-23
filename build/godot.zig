//! Build helpers for launching Godot projects.

/// Options for one Godot process run step.
pub const RunOptions = struct {
    /// Godot executable path; when null, search PATH.
    godot_bin: ?[]const u8 = null,
    /// Project directory, relative to `cwd`.
    project_path: []const u8 = ".",
    /// Pass `--headless`; use for tests and CI.
    headless: bool = false,
    /// Pass `--editor`; use to open the project in the editor.
    editor: bool = false,
    /// Optional `--script` resource path.
    script: ?[]const u8 = null,
    /// Arguments appended after the typed flags. This is the escape hatch for
    /// options the helper does not model yet, such as export flags.
    extra_args: []const []const u8 = &.{},
    /// Working directory for the process; defaults to the build root.
    cwd: ?std.Build.LazyPath = null,
};

/// Resolves the Godot executable from an explicit path or PATH.
pub fn findGodot(b: *std.Build, explicit: ?[]const u8) ?[]const u8 {
    if (explicit) |exe| return exe;
    return b.findProgram(.{ .names = &.{ "godot", "godot4", "godot-4", "godot.exe", "godot4.exe" } });
}

/// Adds a Godot process run step. Arguments are appended dynamically so the
/// same helper can later drive editor/export/custom runs. If no executable is
/// given and none is found on PATH, the returned step fails with an actionable
/// diagnostic instead of panicking during build configuration.
pub fn addRun(b: *std.Build, options: RunOptions) *std.Build.Step {
    const godot_exe = findGodot(b, options.godot_bin) orelse {
        return &b.addFail(
            "Godot executable not found; pass -Dgodot_bin=/path/to/godot or add godot to PATH",
        ).step;
    };

    const run = b.addSystemCommand(&.{godot_exe});
    if (options.headless) run.addArg("--headless");
    if (options.editor) run.addArg("--editor");
    run.addArg("--path");
    run.addArg(options.project_path);
    if (options.script) |script| {
        run.addArg("--script");
        run.addArg(script);
    }
    run.addArgs(options.extra_args);
    run.setCwd(options.cwd orelse b.path("."));
    return &run.step;
}

const std = @import("std");
