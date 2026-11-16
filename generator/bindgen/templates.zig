//! Bindgen template entry points. Bindgen supports template additions; method
//! replacement is codegen-only.

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
    const set = try shared.Set.load(arena, io, "generator/bindgen/custom/templates");
    for (set.classes) |template| {
        if (template.kind != .artifact) return error.UnsupportedTemplateKind;
    }
    for (set.builtins) |template| {
        if (template.kind != .artifact) return error.UnsupportedTemplateKind;
    }
    return set;
}

const Allocator = std.mem.Allocator;
const Io = std.Io;
const std = @import("std");

const shared = @import("../model/templates.zig");
