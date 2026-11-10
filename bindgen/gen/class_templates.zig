//! Hand-maintained class code templates.
//!
//! These are deliberately outside the generic method emitter: construction
//! ownership rules are easy to tweak and should be findable in one place.

pub fn writeConstruct(writer: *Io.Writer, class: *const ExtensionApiJson.Class) !void {
    try writer.writeAll("    pub fn construct(dispatcher: anytype) ?*");
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

const Io = @import("std").Io;

const names = @import("names.zig");
const ExtensionApiJson = @import("../ExtensionApiJson.zig");
