//! Parsed `extension_api.json` schema, limited to the builtin-class data the
//! bindgen needs. Unknown fields are ignored so newer Godot dumps still parse.

builtin_class_sizes: []const BuildConfigurationSizes,
builtin_class_member_offsets: []const BuildConfigurationOffsets,
builtin_classes: []const BuiltinClass,

const ExtensionApiJson = @This();

pub const BuildConfiguration = enum {
    float_32,
    float_64,
    double_32,
    double_64,
};

pub const BuildConfigurationSizes = struct {
    build_configuration: []const u8,
    sizes: []const Size,
};

pub const Size = struct {
    name: []const u8,
    size: usize,
};

pub const BuildConfigurationOffsets = struct {
    build_configuration: []const u8,
    classes: []const ClassOffsets,
};

pub const ClassOffsets = struct {
    name: []const u8,
    members: []const MemberOffset = &.{},
};

pub const MemberOffset = struct {
    member: []const u8,
    offset: usize,
    meta: []const u8,
};

pub const BuiltinClass = struct {
    name: []const u8,
    is_keyed: bool = false,
    has_destructor: bool = false,
    brief_description: ?[]const u8 = null,
    description: ?[]const u8 = null,
    members: []const Member = &.{},
    methods: []const Method = &.{},
    constructors: []const Constructor = &.{},
    operators: []const Operator = &.{},
};

pub const Member = struct {
    name: []const u8,
    type: []const u8,
    description: ?[]const u8 = null,
};

pub const Method = struct {
    name: []const u8,
    return_type: []const u8 = "void",
    is_vararg: bool = false,
    is_const: bool = false,
    is_static: bool = false,
    hash: u32 = 0,
    arguments: []const Argument = &.{},
    description: ?[]const u8 = null,
};

pub const Argument = struct {
    name: []const u8 = "",
    type: []const u8,
    default_value: ?[]const u8 = null,
};

pub const Constructor = struct {
    index: usize,
    arguments: []const Argument = &.{},
    description: ?[]const u8 = null,
};

pub const Operator = struct {
    name: []const u8,
    right_type: ?[]const u8 = null,
    return_type: []const u8,
    description: ?[]const u8 = null,
};

pub fn parse(gpa: Allocator, bytes: []const u8) !json.Parsed(ExtensionApiJson) {
    return json.parseFromSlice(ExtensionApiJson, gpa, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

pub fn sizesFor(self: ExtensionApiJson, config: anytype) ?[]const Size {
    for (self.builtin_class_sizes) |entry| {
        if (std.mem.eql(u8, entry.build_configuration, @tagName(config))) return entry.sizes;
    }
    return null;
}

pub fn offsetsFor(self: ExtensionApiJson, config: anytype) ?[]const ClassOffsets {
    for (self.builtin_class_member_offsets) |entry| {
        if (std.mem.eql(u8, entry.build_configuration, @tagName(config))) return entry.classes;
    }
    return null;
}

test "parse extension api builtin data" {
    const src =
        \\{
        \\  "builtin_class_sizes": [
        \\    {"build_configuration": "float_32", "sizes": [{"name": "AABB", "size": 24}]}
        \\  ],
        \\  "builtin_class_member_offsets": [
        \\    {"build_configuration": "float_32", "classes": [
        \\      {"name": "AABB", "members": [
        \\        {"member": "position", "offset": 0, "meta": "Vector3"},
        \\        {"member": "size", "offset": 12, "meta": "Vector3"}
        \\      ]}
        \\    ]}
        \\  ],
        \\  "builtin_classes": [
        \\    {"name": "AABB", "members": [{"name": "position", "type": "Vector3"}],
        \\     "methods": [{"name": "get_center", "return_type": "Vector3", "hash": 1}],
        \\     "constructors": [{"index": 0}],
        \\     "operators": [{"name": "==", "right_type": "AABB", "return_type": "bool"}]}
        \\  ]
        \\}
    ;

    const parsed = try parse(std.testing.allocator, src);
    defer parsed.deinit();

    const value = parsed.value;
    try std.testing.expectEqual(@as(usize, 24), value.sizesFor(.float_32).?[0].size);
    try std.testing.expectEqual(@as(usize, 12), value.offsetsFor(.float_32).?[0].members[1].offset);
    try std.testing.expectEqualStrings("get_center", value.builtin_classes[0].methods[0].name);
    try std.testing.expectEqualStrings("AABB", value.builtin_classes[0].operators[0].right_type.?);
}

const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
