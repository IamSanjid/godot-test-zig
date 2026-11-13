//! Naming rules shared by the bindgen and codegen builtin emitters.

pub fn constructorName(arena: Allocator, constructor: ExtensionApiJson.Constructor) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);

    for (constructor.arguments, 0..) |argument, index| {
        if (std.mem.eql(u8, argument.name, "from")) {
            try fixed.writeAll("from");
            naming.writeConvert(&fixed, .zig, .type, argument.type) catch return error.IdentifierTooLong;
            for (constructor.arguments, 0..) |other, other_index| {
                if (other_index == index) continue;
                const source = if (other.name.len != 0) other.name else other.type;
                naming.writeConvert(&fixed, .zig, .type, source) catch return error.IdentifierTooLong;
            }
            return arena.dupe(u8, fixed.buffered());
        }
    }

    if (constructor.index == 0) {
        try fixed.writeAll("init");
    } else {
        try fixed.writeAll("init");
        for (constructor.arguments) |argument| {
            const source = if (argument.name.len != 0) argument.name else argument.type;
            naming.writeConvert(&fixed, .zig, .type, source) catch return error.IdentifierTooLong;
        }
    }
    return arena.dupe(u8, fixed.buffered());
}

pub fn operatorName(arena: Allocator, operator: ExtensionApiJson.Operator) ![]const u8 {
    var buf: [160]u8 = undefined;
    var fixed: Io.Writer = .fixed(&buf);
    if (operator.right_type == null) {
        const base = if (std.mem.eql(u8, operator.name, "-") or std.mem.eql(u8, operator.name, "unary-")) "negate" else if (std.mem.eql(u8, operator.name, "+") or std.mem.eql(u8, operator.name, "unary+")) "positive" else if (std.mem.eql(u8, operator.name, "~")) "bitNegate" else if (std.mem.eql(u8, operator.name, "not")) "not" else "op";
        try fixed.writeAll("op");
        try fixed.writeByte(std.ascii.toUpper(base[0]));
        try fixed.writeAll(base[1..]);
        return arena.dupe(u8, fixed.buffered());
    }

    const base = if (std.mem.eql(u8, operator.name, "==")) "eql" else if (std.mem.eql(u8, operator.name, "!=")) "notEql" else if (std.mem.eql(u8, operator.name, "<")) "lt" else if (std.mem.eql(u8, operator.name, "<=")) "lte" else if (std.mem.eql(u8, operator.name, ">")) "gt" else if (std.mem.eql(u8, operator.name, ">=")) "gte" else if (std.mem.eql(u8, operator.name, "+")) "add" else if (std.mem.eql(u8, operator.name, "-")) "sub" else if (std.mem.eql(u8, operator.name, "*")) "mul" else if (std.mem.eql(u8, operator.name, "/")) "div" else if (std.mem.eql(u8, operator.name, "%")) "mod" else if (std.mem.eql(u8, operator.name, "**")) "pow" else if (std.mem.eql(u8, operator.name, "<<")) "shl" else if (std.mem.eql(u8, operator.name, ">>")) "shr" else if (std.mem.eql(u8, operator.name, "&")) "bitAnd" else if (std.mem.eql(u8, operator.name, "|")) "bitOr" else if (std.mem.eql(u8, operator.name, "^")) "bitXor" else if (std.mem.eql(u8, operator.name, "and")) "and" else if (std.mem.eql(u8, operator.name, "or")) "or" else if (std.mem.eql(u8, operator.name, "xor")) "xor" else if (std.mem.eql(u8, operator.name, "not")) "not" else if (std.mem.eql(u8, operator.name, "in")) "in" else "op";
    try fixed.writeAll("op");
    try fixed.writeByte(std.ascii.toUpper(base[0]));
    try fixed.writeAll(base[1..]);
    try fixed.writeAll(operator.right_type.?);
    return arena.dupe(u8, fixed.buffered());
}

pub fn operatorTag(operator: ExtensionApiJson.Operator) []const u8 {
    if (operator.right_type == null) {
        if (std.mem.eql(u8, operator.name, "-") or std.mem.eql(u8, operator.name, "unary-")) return "negate";
        if (std.mem.eql(u8, operator.name, "+") or std.mem.eql(u8, operator.name, "unary+")) return "positive";
        if (std.mem.eql(u8, operator.name, "~")) return "bit_negate";
    }
    const name = operator.name;
    if (std.mem.eql(u8, name, "==")) return "equal";
    if (std.mem.eql(u8, name, "!=")) return "not_equal";
    if (std.mem.eql(u8, name, "<")) return "less";
    if (std.mem.eql(u8, name, "<=")) return "less_equal";
    if (std.mem.eql(u8, name, ">")) return "greater";
    if (std.mem.eql(u8, name, ">=")) return "greater_equal";
    if (std.mem.eql(u8, name, "+")) return "add";
    if (std.mem.eql(u8, name, "-")) return "subtract";
    if (std.mem.eql(u8, name, "*")) return "multiply";
    if (std.mem.eql(u8, name, "/")) return "divide";
    if (std.mem.eql(u8, name, "%")) return "module";
    if (std.mem.eql(u8, name, "**")) return "power";
    if (std.mem.eql(u8, name, "<<")) return "shift_left";
    if (std.mem.eql(u8, name, ">>")) return "shift_right";
    if (std.mem.eql(u8, name, "&")) return "bit_and";
    if (std.mem.eql(u8, name, "|")) return "bit_or";
    if (std.mem.eql(u8, name, "^")) return "bit_xor";
    if (std.mem.eql(u8, name, "~")) return "bit_negate";
    if (std.mem.eql(u8, name, "and")) return "and";
    if (std.mem.eql(u8, name, "or")) return "or";
    if (std.mem.eql(u8, name, "xor")) return "xor";
    if (std.mem.eql(u8, name, "not")) return "not";
    if (std.mem.eql(u8, name, "in")) return "in";
    return "max";
}

pub fn variantTypeName(arena: Allocator, raw: []const u8) ![]const u8 {
    if (std.mem.eql(u8, raw, "Variant")) return arena.dupe(u8, "variant_max");
    if (std.mem.eql(u8, raw, "Nil")) return arena.dupe(u8, "nil");
    return names.snake(arena, raw);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const naming = @import("naming");
const names = @import("names.zig");
const ExtensionApiJson = @import("ExtensionApiJson.zig");
