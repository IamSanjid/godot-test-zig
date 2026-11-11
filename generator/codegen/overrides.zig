//! Method override precedence and emission.
//!
//! Precedence:
//!   1. per-artifact `@replace`
//!   2. matching global template
//!   3. generated method

pub fn write(
    writer: *Io.Writer,
    arena: Allocator,
    custom_sections: *const custom_mod.Sections,
    templates: *const template_mod.Set,
    replacement_used: *[64]bool,
    generated_name: []const u8,
    context: template_mod.RenderContext,
    indent: usize,
) !bool {
    if (custom_sections.replacementIndex(generated_name)) |index| {
        replacement_used[index] = true;
        try custom_mod.writeIndented(writer, custom_sections.replacements[index].code, indent);
        return true;
    }

    if (templates.find(.{
        .artifact = context.artifact,
        .method = generated_name,
    })) |matched| {
        const rendered = try template_mod.render(arena, matched, context);
        try custom_mod.writeIndented(writer, rendered, indent);
        return true;
    }

    return false;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const custom_mod = @import("custom.zig");
const template_mod = @import("templates.zig");

test "per-artifact replacement wins over template" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const custom_sections = custom_mod.Sections{
        .replacements = &.{
            .{ .name = "process", .code = "customProcess" },
        },
    };
    const class_templates = [_]template_mod.Template{
        .{ .method = "process", .code = "templateProcess" },
    };
    const templates = template_mod.Set{ .classes = &class_templates };
    var used: [64]bool = @splat(false);

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const emitted = try write(&aw.writer, arena, &custom_sections, &templates, &used, "process", .{
        .artifact = .class,
        .method = "process",
        .class_name = "Node",
        .binding_class = "classes.core.Node",
    }, 0);
    try std.testing.expect(emitted);
    try std.testing.expect(used[0]);
    try std.testing.expectEqualStrings("customProcess\n", aw.writer.buffered());
}

test "template applies when no custom replacement exists" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const custom_sections = custom_mod.Sections{};
    const class_templates = [_]template_mod.Template{
        .{ .method = "process", .code = "{{Class}}Process" },
    };
    const templates = template_mod.Set{ .classes = &class_templates };
    var used: [64]bool = @splat(false);

    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    const emitted = try write(&aw.writer, arena, &custom_sections, &templates, &used, "process", .{
        .artifact = .class,
        .method = "process",
        .class_name = "Node",
        .binding_class = "classes.core.Node",
    }, 0);
    try std.testing.expect(emitted);
    try std.testing.expectEqualStrings("NodeProcess\n", aw.writer.buffered());
}
