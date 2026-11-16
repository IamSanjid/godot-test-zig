//! Global method templates shared by codegen and bindgen.
//!
//! Each backend loads templates from its own
//! `custom/templates/{classes,builtins}/*.zig.tpl` directory. Codegen supports
//! replacements and artifact additions; bindgen supports artifact additions.

pub const Artifact = enum { class, builtin };

pub const Kind = enum { replace, artifact };

pub const TargetModifier = enum { exact, derived };

pub const Target = struct {
    name: []const u8,
    modifier: TargetModifier = .exact,
};

pub const Template = struct {
    kind: Kind = .replace,
    method: []const u8,
    code: []const u8,
    /// Source file, used for diagnostics.
    source: []const u8 = "",
    /// null means the template applies to every artifact.
    targets: ?[]const Target = null,
};

/// The matcher is centralized so future filters can be added without changing
/// renderers.
pub const TemplateMatch = struct {
    artifact: Artifact,
    method: []const u8,
};

pub const RenderContext = struct {
    artifact: Artifact,
    method: []const u8,
    class_name: ?[]const u8 = null,
    builtin_name: ?[]const u8 = null,
    binding_class: ?[]const u8 = null,
    binding_builtin: ?[]const u8 = null,
    api_type: ?[]const u8 = null,
    dispatcher: []const u8 = "runtime.dispatcher()",
};

pub const Set = struct {
    classes: []const Template = &.{},
    builtins: []const Template = &.{},

    pub fn load(arena: Allocator, io: Io, root: []const u8) !Set {
        var classes: std.ArrayList(Template) = .empty;
        var builtins: std.ArrayList(Template) = .empty;
        const classes_path = try std.fs.path.join(arena, &.{ root, "classes" });
        const builtins_path = try std.fs.path.join(arena, &.{ root, "builtins" });
        try loadDirectory(arena, io, classes_path, .class, &classes);
        try loadDirectory(arena, io, builtins_path, .builtin, &builtins);
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

    /// Return the templates that apply to one concrete artifact type.
    /// `ancestors` includes the type itself followed by its base types.
    pub fn filtered(
        self: Set,
        arena: Allocator,
        artifact: Artifact,
        type_name: []const u8,
        ancestors: []const []const u8,
    ) !Set {
        var items: std.ArrayList(Template) = .empty;
        for (self.list(artifact)) |template| {
            if (!matchesTarget(template, artifact, type_name, ancestors)) continue;
            try items.append(arena, template);
        }
        return switch (artifact) {
            .class => .{ .classes = items.items },
            .builtin => .{ .builtins = items.items },
        };
    }

    pub fn validate(self: Set, api: ExtensionApiJson) !void {
        for (self.classes) |template| {
            const targets = template.targets orelse continue;
            for (targets) |target| {
                if (!hasClass(api, target.name)) {
                    std.log.err("Unknown @templates_for class target `{s}` in {s}", .{ target.name, template.source });
                    return error.UnknownTemplateTarget;
                }
            }
        }
        for (self.builtins) |template| {
            const targets = template.targets orelse continue;
            for (targets) |target| {
                if (!hasBuiltin(api, target.name) or types.isPrimitive(target.name)) {
                    std.log.err("Unknown or non-generated @templates_for builtin target `{s}` in {s}", .{ target.name, template.source });
                    return error.UnknownTemplateTarget;
                }
            }
        }
    }

    pub fn find(self: Set, match: TemplateMatch) ?Template {
        for (self.list(match.artifact)) |template| {
            if (template.kind != .replace) continue;
            if (std.mem.eql(u8, template.method, match.method)) return template;
        }
        return null;
    }
};

fn matchesTarget(
    template: Template,
    artifact: Artifact,
    type_name: []const u8,
    ancestors: []const []const u8,
) bool {
    const targets = template.targets orelse return true;
    for (targets) |target| {
        if (std.mem.eql(u8, type_name, target.name)) return true;
        if (artifact == .class and target.modifier == .derived) {
            for (ancestors) |ancestor| {
                if (std.mem.eql(u8, ancestor, target.name)) return true;
            }
        }
    }
    return false;
}

fn hasClass(api: ExtensionApiJson, name: []const u8) bool {
    for (api.classes) |class| {
        if (std.mem.eql(u8, class.name, name)) return true;
    }
    return false;
}

fn hasBuiltin(api: ExtensionApiJson, name: []const u8) bool {
    for (api.builtin_classes) |builtin| {
        if (std.mem.eql(u8, builtin.name, name)) return true;
    }
    return false;
}

fn loadDirectory(
    arena: Allocator,
    io: Io,
    path: []const u8,
    artifact: Artifact,
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
        try parseFile(arena, raw, file_path, artifact, out);
    }
}

fn parseFile(
    arena: Allocator,
    raw: []const u8,
    source: []const u8,
    artifact: Artifact,
    out: *std.ArrayList(Template),
) !void {
    var targets_text: ?[]const u8 = null;
    var saw_section = false;
    var inside_section = false;

    var scan = std.mem.splitScalar(u8, raw, '\n');
    while (scan.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, trimmed, "// @section ")) {
            saw_section = true;
            inside_section = true;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "// @section_end")) {
            inside_section = false;
            continue;
        }
        if (!std.mem.startsWith(u8, trimmed, "// @templates_for")) continue;
        if (inside_section) return error.TemplatesForInsideTemplate;
        if (saw_section) return error.TemplatesForAfterTemplate;
        if (targets_text != null) return error.DuplicateTemplatesFor;
        targets_text = std.mem.trim(u8, trimmed["// @templates_for".len..], " \t");
    }

    const targets = if (targets_text) |text| try parseTargets(arena, artifact, text) else null;
    const sections = custom.parse(arena, raw) catch |err| switch (err) {
        error.DuplicateCustomSection => return error.DuplicateTemplate,
        else => return err,
    };
    for (sections.sections) |section| {
        const kind: Kind = switch (section.placement) {
            .replace => .replace,
            .artifact => .artifact,
            else => return error.InvalidTemplateSection,
        };
        for (out.items) |existing| {
            if (std.mem.eql(u8, existing.method, section.name)) return error.DuplicateTemplate;
        }
        try out.append(arena, .{
            .kind = kind,
            .method = section.name,
            .code = section.code,
            .source = source,
            .targets = targets,
        });
    }
}
fn parseTargets(
    arena: Allocator,
    artifact: Artifact,
    text: []const u8,
) !?[]const Target {
    if (text.len == 0) return error.InvalidTemplateTarget;
    if (std.mem.eql(u8, text, "*")) return null;

    var targets: std.ArrayList(Target) = .empty;
    var selectors = std.mem.splitScalar(u8, text, ',');
    while (selectors.next()) |raw_selector| {
        const selector = std.mem.trim(u8, raw_selector, " \t");
        if (selector.len == 0) return error.InvalidTemplateTarget;

        var type_name = selector;
        var modifier: TargetModifier = .exact;
        if (std.mem.indexOfScalar(u8, selector, ':')) |colon| {
            type_name = std.mem.trim(u8, selector[0..colon], " \t");
            const modifier_text = std.mem.trim(u8, selector[colon + 1 ..], " \t");
            if (std.mem.eql(u8, modifier_text, "exact")) {
                modifier = .exact;
            } else if (std.mem.eql(u8, modifier_text, "derived")) {
                modifier = .derived;
            } else {
                return error.InvalidTemplateModifier;
            }
        }
        if (type_name.len == 0 or !std.zig.isValidId(type_name)) return error.InvalidTemplateTarget;
        if (artifact == .builtin and modifier != .exact) return error.DerivedTargetOnBuiltin;

        var duplicate = false;
        for (targets.items) |existing| {
            if (std.mem.eql(u8, existing.name, type_name) and existing.modifier == modifier) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) {
            try targets.append(arena, .{ .name = try arena.dupe(u8, type_name), .modifier = modifier });
        }
    }
    if (targets.items.len == 0) return error.InvalidTemplateTarget;
    return targets.items;
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
    if (std.mem.eql(u8, placeholder, "dispatcher")) return context.dispatcher;
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
const ExtensionApiJson = @import("ExtensionApiJson.zig");
const custom = @import("custom.zig");
const types = @import("types.zig");

test "template files parse and render placeholders" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try parseFile(arena,
        \\// @section replace doThing
        \\pub inline fn doThing(self: *{{Class}}) void {
        \\    bindings.{{binding_class}}.doThing(@ptrCast(self), {{dispatcher}});
        \\}
        \\// @section_end replace doThing
        \\// @section artifact extra
        \\pub inline fn extra(self: *{{Class}}) void {
        \\    _ = self;
        \\}
        \\// @section_end artifact extra
    , "<test>", .class, &list);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(Kind.replace, list.items[0].kind);
    try std.testing.expectEqual(Kind.artifact, list.items[1].kind);
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
        \\// @section replace process
        \\// @section_end replace process
        \\// @section replace process
        \\// @section_end replace process
    , "<test>", .class, &list));
}

test "templates_for selects exact and derived classes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try parseFile(arena,
        \\// @templates_for Control, Node:derived
        \\// @section replace process
        \\// @section_end replace process
    , "<test>", .class, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(@as(usize, 2), list.items[0].targets.?.len);

    const set = Set{ .classes = list.items };
    const control = try set.filtered(arena, .class, "Control", &.{ "Control", "Node", "Object" });
    try std.testing.expectEqual(@as(usize, 1), control.classes.len);

    const label = try set.filtered(arena, .class, "Label", &.{ "Label", "Control", "Node", "Object" });
    try std.testing.expectEqual(@as(usize, 1), label.classes.len);

    const object = try set.filtered(arena, .class, "Object", &.{"Object"});
    try std.testing.expectEqual(@as(usize, 0), object.classes.len);
}

test "templates_for * selects every class" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try parseFile(arena,
        \\// @templates_for *
        \\// @section artifact extra
        \\// @section_end artifact extra
    , "<test>", .class, &list);
    try std.testing.expect(list.items[0].targets == null);

    const set = Set{ .classes = list.items };
    const filtered = try set.filtered(arena, .class, "Anything", &.{"Anything"});
    try std.testing.expectEqual(@as(usize, 1), filtered.classes.len);
}

test "templates_for rejects derived builtins" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try std.testing.expectError(error.DerivedTargetOnBuiltin, parseFile(arena,
        \\// @templates_for PackedByteArray:derived
        \\// @section artifact extra
        \\// @section_end artifact extra
    , "<test>", .builtin, &list));
}

test "keyword method names are accepted" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var list: std.ArrayList(Template) = .empty;
    try parseFile(arena,
        \\// @section replace align
        \\// @section_end replace align
    , "<test>", .class, &list);
    try std.testing.expectEqualStrings("align", list.items[0].method);
}
