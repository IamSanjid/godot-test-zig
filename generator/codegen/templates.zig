//! Global codegen method templates.
//!
//! Templates live under `generator/codegen/custom/templates/{classes,builtins}/*.zig.tpl`.
//! They are read and rendered into generated files; they are never written.

pub const Artifact = enum { class, builtin };

pub const Kind = enum { replace, method };

pub const Template = struct {
    kind: Kind = .replace,
    method: []const u8,
    code: []const u8,
};

/// The matcher is centralized so future `@template_for` / `@template_skip`
/// filters can be added without changing renderers.
pub const TemplateMatch = struct {
    artifact: Artifact,
    method: []const u8,
    types: ?[]const []const u8 = null,
    skip: ?[]const []const u8 = null,
};

pub const RenderContext = struct {
    artifact: Artifact,
    method: []const u8,
    class_name: ?[]const u8 = null,
    builtin_name: ?[]const u8 = null,
    binding_class: ?[]const u8 = null,
    binding_builtin: ?[]const u8 = null,
    api_type: ?[]const u8 = null,
};

pub const Set = struct {
    classes: []const Template = &.{},
    builtins: []const Template = &.{},

    pub fn load(arena: Allocator, io: Io) !Set {
        var classes: std.ArrayList(Template) = .empty;
        var builtins: std.ArrayList(Template) = .empty;
        try loadDirectory(arena, io, "generator/codegen/custom/templates/classes", &classes);
        try loadDirectory(arena, io, "generator/codegen/custom/templates/builtins", &builtins);
        return .{
            .classes = classes.items,
            .builtins = builtins.items,
        };
    }

    pub fn list(self: Set, artifact: Artifact) []const Template {
        return switch (artifact) {
            .class => self.classes,
            .builtin => self.builtins,
        };
    }

    pub fn find(self: Set, match: TemplateMatch) ?Template {
        for (self.list(match.artifact)) |template| {
            if (template.kind != .replace) continue;
            if (std.mem.eql(u8, template.method, match.method)) return template;
        }
        return null;
    }
};

fn loadDirectory(
    arena: Allocator,
    io: Io,
    path: []const u8,
    out: *std.ArrayList(Template),
) !void {
    var dir = Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close(io);

    var names: [128][]const u8 = undefined;
    var count: usize = 0;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig.tpl")) continue;
        if (count == names.len) return error.TooManyTemplateFiles;
        names[count] = try arena.dupe(u8, entry.name);
        count += 1;
    }
    std.mem.sort([]const u8, names[0..count], {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    for (names[0..count]) |name| {
        const file_path = try std.fs.path.join(arena, &.{ path, name });
        const raw_input = try Io.Dir.cwd().readFileAlloc(io, file_path, arena, .unlimited);
        const raw = if (std.mem.startsWith(u8, raw_input, "\xEF\xBB\xBF")) raw_input[3..] else raw_input;
        try parseFile(arena, raw, out);
    }
}

fn parseFile(arena: Allocator, raw: []const u8, out: *std.ArrayList(Template)) !void {
    var mode: enum { none, replace, method } = .none;
    var current_name: []const u8 = "";
    var current_aw: Io.Writer.Allocating = undefined;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, trimmed, "// @template_end")) {
            const name = std.mem.trim(u8, trimmed["// @template_end".len..], " ");
            const kind: Kind = switch (mode) {
                .replace => .replace,
                .method => .method,
                .none => return error.UnexpectedTemplateEnd,
            };
            if (!std.mem.eql(u8, current_name, name)) return error.MismatchedTemplateEnd;
            const code = try arena.dupe(u8, current_aw.writer.buffered());
            for (out.items) |existing| {
                if (std.mem.eql(u8, existing.method, current_name)) return error.DuplicateTemplate;
            }
            try out.append(arena, .{ .kind = kind, .method = current_name, .code = code });
            mode = .none;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @template replace ")) {
            if (mode != .none) return error.UnclosedTemplate;
            const name = std.mem.trim(u8, trimmed["// @template replace ".len..], " ");
            if (name.len == 0 or !std.zig.isValidId(name)) return error.InvalidTemplateMethod;
            current_name = try arena.dupe(u8, name);
            current_aw = .init(arena);
            mode = .replace;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @template method ")) {
            if (mode != .none) return error.UnclosedTemplate;
            const name = std.mem.trim(u8, trimmed["// @template method ".len..], " ");
            if (name.len == 0 or !std.zig.isValidId(name)) return error.InvalidTemplateMethod;
            current_name = try arena.dupe(u8, name);
            current_aw = .init(arena);
            mode = .method;
            continue;
        }

        switch (mode) {
            .none => {},
            .replace, .method => try current_aw.writer.print("{s}\n", .{line}),
        }
    }
    if (mode != .none) return error.UnclosedTemplate;
}

pub fn render(arena: Allocator, template: Template, context: RenderContext) ![]const u8 {
    var aw: Io.Writer.Allocating = .init(arena);
    var index: usize = 0;
    while (index < template.code.len) {
        if (std.mem.startsWith(u8, template.code[index..], "{{")) {
            const close = std.mem.indexOf(u8, template.code[index + 2 ..], "}}") orelse
                return error.UnclosedTemplatePlaceholder;
            const end = index + 2 + close;
            const placeholder = template.code[index + 2 .. end];
            const replacement = try placeholderValue(placeholder, context);
            try aw.writer.writeAll(replacement);
            index = end + 2;
            continue;
        }
        try aw.writer.writeByte(template.code[index]);
        index += 1;
    }
    return aw.writer.buffered();
}

fn placeholderValue(placeholder: []const u8, context: RenderContext) ![]const u8 {
    if (std.mem.eql(u8, placeholder, "dispatcher")) return "runtime.dispatcher()";
    if (std.mem.eql(u8, placeholder, "method")) return context.method;
    if (std.mem.eql(u8, placeholder, "Class")) {
        return context.class_name orelse error.InvalidTemplatePlaceholder;
    }
    if (std.mem.eql(u8, placeholder, "Builtin")) {
        return context.builtin_name orelse error.InvalidTemplatePlaceholder;
    }
    if (std.mem.eql(u8, placeholder, "binding_class")) {
        return context.binding_class orelse error.InvalidTemplatePlaceholder;
    }
    if (std.mem.eql(u8, placeholder, "binding_builtin")) {
        return context.binding_builtin orelse error.InvalidTemplatePlaceholder;
    }
    if (std.mem.eql(u8, placeholder, "api_type")) {
        return context.api_type orelse "";
    }
    return error.InvalidTemplatePlaceholder;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

test "template files parse and render placeholders" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try parseFile(arena,
        \\// @template replace doThing
        \\pub inline fn doThing(self: *{{Class}}) void {
        \\    bindings.{{binding_class}}.doThing(@ptrCast(self), {{dispatcher}});
        \\}
        \\// @template_end doThing
        \\// @template method extra
        \\pub inline fn extra(self: *{{Class}}) void {
        \\    _ = self;
        \\}
        \\// @template_end extra
    , &list);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(Kind.replace, list.items[0].kind);
    try std.testing.expectEqual(Kind.method, list.items[1].kind);
    const rendered = try render(arena, list.items[0], .{
        .artifact = .class,
        .method = "do_thing",
        .class_name = "Node",
        .binding_class = "classes.core.Node",
        .api_type = "core",
    });
    try std.testing.expect(std.mem.indexOf(u8, rendered, "*Node") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "bindings.classes.core.Node.doThing") != null);
}

test "template duplicate methods are rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try std.testing.expectError(error.DuplicateTemplate, parseFile(arena,
        \\// @template replace process
        \\// @template_end process
        \\// @template replace process
        \\// @template_end process
    , &list));
}
