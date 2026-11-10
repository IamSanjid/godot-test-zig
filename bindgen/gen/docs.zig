//! Doc-comment formatting for `extension_api.json` descriptions.
//!
//! Godot's docs use BBCode-like tags. Generated Zig docs use Markdown-ish
//! equivalents so the output stays readable.

pub fn write(
    writer: *Io.Writer,
    arena: Allocator,
    description: ?[]const u8,
    indent: usize,
    prefix: []const u8,
) !void {
    const text = description orelse return;
    const markdown = try markdownText(arena, text);
    var lines = std.mem.splitScalar(u8, markdown, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        for (0..indent) |_| try writer.writeByte(' ');
        if (trimmed.len == 0) {
            try writer.print("{s}\n", .{prefix});
        } else {
            try writer.print("{s} ", .{prefix});
            try writeLine(writer, trimmed);
            try writer.writeAll("\n");
        }
    }
}

pub fn markdownText(arena: Allocator, text: []const u8) ![]const u8 {
    var aw: Io.Writer.Allocating = .init(arena);

    var index: usize = 0;
    while (index < text.len) {
        if (text[index] != '[') {
            try aw.writer.writeByte(text[index]);
            index += 1;
            continue;
        }

        const close = std.mem.indexOfScalar(u8, text[index + 1 ..], ']') orelse {
            try aw.writer.writeAll(text[index..]);
            break;
        };
        const end = index + 1 + close;
        const body = text[index + 1 .. end];
        const closing = body.len != 0 and body[0] == '/';
        const name = if (closing) body[1..] else body;
        const name_end = std.mem.indexOfAny(u8, name, " =") orelse name.len;

        if (tagReplacement(name[0..name_end], closing)) |replacement| {
            try aw.writer.writeAll(replacement);
        } else {
            try aw.writer.writeAll(text[index .. end + 1]);
        }
        index = end + 1;
    }

    return aw.writer.buffered();
}

fn tagReplacement(tag: []const u8, closing: bool) ?[]const u8 {
    if (closing) {
        if (std.mem.eql(u8, tag, "codeblock") or std.mem.eql(u8, tag, "codeblocks")) return "```";
        if (std.mem.eql(u8, tag, "code")) return "`";
        if (std.mem.eql(u8, tag, "b")) return "**";
        if (std.mem.eql(u8, tag, "i")) return "*";
        if (std.mem.eql(u8, tag, "gdscript") or std.mem.eql(u8, tag, "csharp")) return "";
        return null;
    }

    if (std.mem.eql(u8, tag, "codeblock") or std.mem.eql(u8, tag, "codeblocks")) return "```";
    if (std.mem.eql(u8, tag, "code")) return "`";
    if (std.mem.eql(u8, tag, "b")) return "**";
    if (std.mem.eql(u8, tag, "i")) return "*";
    if (std.mem.eql(u8, tag, "gdscript")) return "## gdscript";
    if (std.mem.eql(u8, tag, "csharp")) return "## csharp";
    return null;
}

test "markdown tags ignore attributes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const result = try markdownText(arena_state.allocator(),
        \\[codeblock lang=text]
        \\hello
        \\[/codeblock]
        \\[code skip-lint]x[/code] [param y]
    );
    try std.testing.expectEqualStrings(
        \\```
        \\hello
        \\```
        \\`x` [param y]
    , result);
}

fn writeLine(writer: *Io.Writer, line: []const u8) !void {
    for (line) |c| {
        if (c == '\t') {
            try writer.writeAll("    ");
        } else {
            try writer.writeByte(c);
        }
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
