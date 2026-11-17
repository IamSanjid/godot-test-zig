//! Hand-maintained class code templates.
//!
//! These are deliberately outside the generic method emitter: construction
//! ownership rules are easy to tweak and should be findable in one place.

/// Emits generated constructors for an instantiable class.
///
/// * `construct` is the primary constructor: uses `classdb_construct_object3`.
///   It does **not** send `NOTIFICATION_POSTINITIALIZE`; callers that need the
///   fully initialized state must send it explicitly. It also does not call
///   `initRef`; `classdb_construct_object3` returns RefCounted with refcount 1.
/// * `constructLegacy` uses `classdb_construct_object`, which sends
///   `NOTIFICATION_POSTINITIALIZE` internally and needs the explicit `initRef`
///   for RefCounted. Keep it only for code that needs the old behavior.
pub fn writeConstruct(writer: *Io.Writer, class: *const ExtensionApiJson.Class, strip_deprecation: bool) !void {
    if (!strip_deprecation) try writeLegacyConstruct(writer, class);
    try writeNonPostInitializingConstruct(writer, class);
}

fn writeLegacyConstruct(writer: *Io.Writer, class: *const ExtensionApiJson.Class) !void {
    try writer.writeAll("    /// Legacy constructor.\n");
    try writer.writeAll("    ///\n");
    try writer.writeAll("    /// Uses `classdb_construct_object`, which sends `NOTIFICATION_POSTINITIALIZE`\n");
    try writer.writeAll("    /// internally. For RefCounted, this additionally calls `init_ref`; that is\n");
    try writer.writeAll("    /// not needed for objects created through `construct`.\n");
    try writer.writeAll("    pub fn constructLegacy(dispatcher: anytype) ?*");
    try names.writeRawIdent(writer, class.name);
    try writer.writeAll(" {\n");
    try writer.writeAll("        var class_name = StringName.fromComptimeLatin1(dispatcher, \"");
    try names.writeEscaped(writer, class.name);
    try writer.writeAll("\");\n");
    try writer.writeAll("        const self: ?*");
    try names.writeRawIdent(writer, class.name);
    try writer.writeAll(" = @ptrCast(dispatcher.dispatch(.classdb_construct_object, .{@ptrCast(&class_name)}));\n");
    if (class.is_refcounted) {
        try writer.writeAll("        if (self) |instance| {\n");
        try writer.writeAll("            _ = instance.initRef(dispatcher);\n");
        try writer.writeAll("        }\n");
    }
    try writer.writeAll("        return self;\n    }\n\n");
}

/// Primary constructor: does not post-initialize and does not call `init_ref`.
/// Used by `CreateInstance`; the create-instance callback sends post-initialize
/// after attaching the extension instance when the engine asks for it.
fn writeNonPostInitializingConstruct(writer: *Io.Writer, class: *const ExtensionApiJson.Class) !void {
    try writer.writeAll("    /// Primary constructor.\n");
    try writer.writeAll("    ///\n");
    try writer.writeAll("    /// Does **not** send `NOTIFICATION_POSTINITIALIZE`; send it explicitly if the\n");
    try writer.writeAll("    /// object must be fully initialized. `init_ref` is not needed: for RefCounted\n");
    try writer.writeAll("    /// `classdb_construct_object3` returns with refcount 1.\n");
    try writer.writeAll("    /// The caller owns that reference for RefCounted classes.\n");
    try writer.writeAll("    pub fn construct(dispatcher: anytype) ?*");
    try names.writeRawIdent(writer, class.name);
    try writer.writeAll(" {\n");
    try writer.writeAll("        var class_name = StringName.fromComptimeLatin1(dispatcher, \"");
    try names.writeEscaped(writer, class.name);
    try writer.writeAll("\");\n");
    try writer.writeAll("        return @ptrCast(dispatcher.dispatch(.classdb_construct_object3, .{@ptrCast(&class_name)}));\n");
    try writer.writeAll("    }\n\n");
}

const std = @import("std");
const Io = std.Io;

const names = @import("../model/names.zig");
const ExtensionApiJson = @import("../model/ExtensionApiJson.zig");

test "construct and constructLegacy output" {
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const class: ExtensionApiJson.Class = .{
        .name = "Example",
        .is_refcounted = true,
        .is_instantiable = true,
    };
    try writeConstruct(&aw.writer, &class, false);
    const output = aw.writer.buffered();

    // Legacy constructor keeps the post-initializing behavior.
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn constructLegacy(dispatcher: anytype) ?*Example {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".classdb_construct_object, ") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_ = instance.initRef(dispatcher);") != null);

    // Primary constructor is non-post-initializing and refcount-aware.
    const extension_start = std.mem.indexOf(u8, output, "pub fn construct(dispatcher: anytype) ?*Example {") orelse
        return error.MissingConstruct;
    try std.testing.expect(std.mem.indexOf(u8, output, ".classdb_construct_object3, ") != null);
    const extension = output[extension_start..];
    try std.testing.expect(std.mem.indexOf(u8, extension, "POSTINITIALIZE") == null);
    try std.testing.expect(std.mem.indexOf(u8, extension, "initRef") == null);
    try std.testing.expect(std.mem.indexOf(u8, extension, "classdb_construct_object, ") == null);

    var stripped: Io.Writer.Allocating = .init(std.testing.allocator);
    defer stripped.deinit();
    try writeConstruct(&stripped.writer, &class, true);
    try std.testing.expect(std.mem.indexOf(u8, stripped.writer.buffered(), "constructLegacy") == null);
}
