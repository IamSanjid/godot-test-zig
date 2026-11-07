_copyright: Description,
@"$schema": []const u8,
format_version: u32,
types: []const TypeDecl,
interface: []const InterfaceFunction,

const InterfaceJson = @This();

pub const Description = []const []const u8;

pub const Deprecated = struct {
    since: []const u8,
    message: ?[]const u8 = null,
    replace_with: ?[]const u8 = null,
};

// ---- payloads for each `kind` ----------------------------------------

pub const EnumValue = struct {
    name: []const u8,
    value: i64,
    description: ?Description = null,
};

pub const EnumType = struct {
    is_bitfield: bool = false,
    values: []const EnumValue,
};

pub const HandleType = struct {
    parent: ?[]const u8 = null,
    is_const: bool = false,
    is_uninitialized: bool = false,
};

pub const AliasType = struct {
    type: []const u8,
};

pub const Member = struct {
    name: []const u8,
    type: []const u8,
    description: ?Description = null,
};

pub const StructType = struct {
    members: []const Member,
};

pub const Argument = struct {
    type: []const u8,
    name: ?[]const u8 = null,
    description: ?Description = null,
};

pub const ReturnValue = struct {
    type: []const u8,
    description: ?Description = null,
};

pub const FunctionType = struct {
    return_value: ?ReturnValue = null,
    arguments: []const Argument,
};

// ---- "types" entries: internally tagged on `kind` --------------------

pub const TypeDecl = struct {
    name: []const u8,
    description: ?Description = null,
    deprecated: ?Deprecated = null,
    data: Data,

    pub const Data = union(enum) {
        @"enum": EnumType,
        handle: HandleType,
        alias: AliasType,
        @"struct": StructType,
        function: FunctionType,
    };

    /// Fields shared by every kind, plus the discriminator.
    const Common = struct {
        name: []const u8,
        kind: []const u8,
        description: ?Description = null,
        deprecated: ?Deprecated = null,
    };

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) json.ParseError(@TypeOf(source.*))!TypeDecl {
        const value = try json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: json.Value,
        options: json.ParseOptions,
    ) json.ParseFromValueError!TypeDecl {
        if (source != .object) return error.UnexpectedToken;

        // Each pass sees keys that belong to the other struct, so ignore unknowns.
        var lenient = options;
        lenient.ignore_unknown_fields = true;

        const common = try json.parseFromValueLeaky(Common, allocator, source, lenient);

        const tag = std.meta.stringToEnum(std.meta.Tag(Data), common.kind) orelse
            return error.InvalidEnumTag;

        const data: Data = switch (tag) {
            inline else => |t| @unionInit(
                Data,
                @tagName(t),
                try json.parseFromValueLeaky(@FieldType(Data, @tagName(t)), allocator, source, lenient),
            ),
        };

        return .{
            .name = common.name,
            .description = common.description,
            .deprecated = common.deprecated,
            .data = data,
        };
    }
};

// ---- "interface" entries and the root document -----------------------

pub const InterfaceFunction = struct {
    name: []const u8,
    return_value: ?ReturnValue = null,
    arguments: []const Argument,
    description: Description,
    since: []const u8,
    deprecated: ?Deprecated = null,
    see: ?[]const []const u8 = null,
    legacy_type_name: ?[]const u8 = null,
};

pub fn parse(gpa: Allocator, bytes: []const u8) !json.Parsed(InterfaceJson) {
    return json.parseFromSlice(InterfaceJson, gpa, bytes, .{
        .allocate = .alloc_always, // don't alias `bytes`
    });
}

test "parse tagged types" {
    const src =
        \\{
        \\  "_copyright": ["x"],
        \\  "$schema": "./gdextension_interface.schema.json",
        \\  "format_version": 1,
        \\  "types": [
        \\    {"name": "Flags", "kind": "enum", "is_bitfield": true,
        \\     "values": [{"name": "A", "value": 1}]},
        \\    {"name": "Obj", "kind": "handle", "is_const": true},
        \\    {"name": "Int", "kind": "alias", "type": "int64_t"},
        \\    {"name": "S", "kind": "struct",
        \\     "members": [{"name": "x", "type": "float"}]},
        \\    {"name": "Cb", "kind": "function",
        \\     "arguments": [{"type": "void*"}]}
        \\  ],
        \\  "interface": []
        \\}
    ;
    const parsed = try parse(std.testing.allocator, src);
    defer parsed.deinit();

    const types = parsed.value.types;
    try std.testing.expect(types[0].data == .@"enum");
    try std.testing.expect(types[0].data.@"enum".is_bitfield);
    try std.testing.expect(types[1].data.handle.is_const);
    try std.testing.expectEqualStrings("int64_t", types[2].data.alias.type);
    try std.testing.expectEqual(1, types[3].data.@"struct".members.len);
    try std.testing.expect(types[4].data == .function);
}

const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
