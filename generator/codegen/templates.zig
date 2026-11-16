//! Codegen template entry points. The parser, matcher, and renderer are shared
//! with bindgen in `model/templates.zig`.

pub const Artifact = shared.Artifact;
pub const Kind = shared.Kind;
pub const TargetModifier = shared.TargetModifier;
pub const Target = shared.Target;
pub const Template = shared.Template;
pub const TemplateMatch = shared.TemplateMatch;
pub const RenderContext = shared.RenderContext;
pub const Set = shared.Set;
pub const render = shared.render;

pub fn load(arena: Allocator, io: Io) !Set {
    return shared.Set.load(arena, io, "generator/codegen/custom/templates");
}

const Allocator = std.mem.Allocator;
const Io = std.Io;
const std = @import("std");

const shared = @import("../model/templates.zig");
