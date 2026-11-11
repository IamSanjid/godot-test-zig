//! Shared API-type spelling helpers.
//!
//! The primitive mappings and build-configuration selection are identical for
//! bindings and codegen outputs.

pub fn realTypeName(conf: api_options.BuiltinBuildConf) []const u8 {
    return switch (conf) {
        .float_32, .float_64 => "f32",
        .double_32, .double_64 => "f64",
    };
}

pub fn pointerAlign(conf: api_options.BuiltinBuildConf) usize {
    return switch (conf) {
        .float_32, .double_32 => 4,
        .float_64, .double_64 => 8,
    };
}

pub fn isPrimitive(raw: []const u8) bool {
    return std.mem.eql(u8, raw, "float") or
        std.mem.eql(u8, raw, "int") or
        std.mem.eql(u8, raw, "bool") or
        std.mem.eql(u8, raw, "void") or
        std.mem.eql(u8, raw, "Nil");
}

pub fn writeApiType(writer: *Io.Writer, raw: []const u8, real_name: []const u8) !void {
    if (std.mem.eql(u8, raw, "float")) return writer.writeAll(real_name);
    if (std.mem.eql(u8, raw, "int")) return writer.writeAll("i64");
    if (std.mem.eql(u8, raw, "bool")) return writer.writeAll("bool");
    if (std.mem.eql(u8, raw, "void") or std.mem.eql(u8, raw, "Nil")) return writer.writeAll("void");
    return names.writeRawIdent(writer, raw);
}

pub fn writeMetaType(writer: *Io.Writer, meta: []const u8, real_name: []const u8) !void {
    if (std.mem.eql(u8, meta, "float")) return writer.writeAll(real_name);
    if (std.mem.eql(u8, meta, "int32")) return writer.writeAll("i32");
    if (std.mem.eql(u8, meta, "int64")) return writer.writeAll("i64");
    if (std.mem.eql(u8, meta, "bool")) return writer.writeAll("bool");
    return names.writeRawIdent(writer, meta);
}

const std = @import("std");
const Io = std.Io;

const names = @import("names.zig");
const api_options = @import("api_options.zig");
