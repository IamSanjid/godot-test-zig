//! Bindgen custom-code sections.
//!
//! Custom files mirror the generated file path relative to the output root, but
//! live under `generator/bindgen/custom/`. The section format is shared with
//! codegen; bindgen consumes file, artifact, extension-target, and replacement
//! sections.

pub const ExtensionSection = shared.ExtensionSection;
pub const Sections = shared.Sections;
pub const writeRaw = shared.writeRaw;
pub const writeIndented = shared.writeIndented;

/// Reads `generator/bindgen/custom/<relative_path>`.
pub fn readForOutput(
    arena: Allocator,
    io: Io,
    relative_path: []const u8,
) !?Sections {
    return shared.read(arena, io, "generator/bindgen/custom", relative_path);
}

pub fn parse(arena: Allocator, raw: []const u8) !Sections {
    return shared.parse(arena, raw);
}

const Allocator = std.mem.Allocator;
const Io = std.Io;
const std = @import("std");

const shared = @import("../model/custom.zig");
