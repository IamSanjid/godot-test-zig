//! Bindgen custom-code sections.
//!
//! Custom files mirror the generated file path relative to the output root, but
//! live under `generator/bindgen/custom/`. The section format is shared with
//! codegen; bindgen consumes file, artifact, and nested-target sections.

pub const StructSection = shared.StructSection;
pub const Sections = shared.Sections;
pub const writeRaw = shared.writeRaw;
pub const writeIndented = shared.writeIndented;

/// Reads `generator/bindgen/custom/<relative_path>`.
pub fn readForOutput(
    arena: Allocator,
    io: Io,
    relative_path: []const u8,
) !?Sections {
    const sections = try shared.read(arena, io, "generator/bindgen/custom", relative_path);
    if (sections) |value| {
        if (value.hasPlacement(.replace)) return error.UnsupportedCustomPlacement;
    }
    return sections;
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    return shared.parse(arena, raw);
}

const Allocator = std.mem.Allocator;
const Io = std.Io;
const std = @import("std");

const shared = @import("../model/custom.zig");
