//! Codegen custom overlays.
//!
//! Custom files mirror the generated artifact path below `generator/codegen/custom/`.
//! The section format is shared with bindgen; codegen consumes file, artifact,
//! and replacement sections. `extend` sections are bindgen-only: codegen has no
//! separate generated bodies to attach them to.

pub const Sections = shared.Sections;
pub const Section = shared.Section;
pub const writeRaw = shared.writeRaw;
pub const writeIndented = shared.writeIndented;

pub fn read(arena: Allocator, io: Io, relative_path: []const u8) !?Sections {
    const sections = try shared.read(arena, io, "generator/codegen/custom", relative_path);
    if (sections) |value| {
        if (value.hasPlacement(.extend)) return error.UnsupportedCustomPlacement;
    }
    return sections;
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    return shared.parse(arena, raw);
}

/// Constants/enums/native/singletons do not have artifact overlays yet. Warn if
/// a user starts relying on them instead of silently ignoring the files.
pub fn warnUnsupportedArtifacts(arena: Allocator, io: Io) !void {
    const relative_paths = [_][]const u8{
        "constants.zig",
        "enums.zig",
        "native.zig",
        "singletons.zig",
    };
    for (relative_paths) |relative_path| {
        const path = try std.fs.path.join(arena, &.{ "generator/codegen/custom", relative_path });
        _ = Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        std.log.warn("Codegen custom overlay `{s}` is not handled yet; ignoring it.", .{path});
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const shared = @import("../model/custom.zig");
