interface_json: []const u8,
/// Godot's `extension_api.json` dump.
extension_api_json: []const u8,
output_dir: []const u8,
/// Builtin layout configuration selected from `builtin_class_sizes` and
/// `builtin_class_member_offsets`.
builtin_build_conf: BuiltinBuildConf = .float_64,
interface_import: []const u8 = "godot_interface",
/// How members of generated `extern struct`s are initialized.
member_initialization: MemberInitialization = .none,
/// Omit deprecated types and interface functions from the generated wrapper.
strip_deprecation: bool = false,

const Options = @This();

pub const BuiltinBuildConf = enum {
    float_32,
    float_64,
    double_32,
    double_64,
};

pub const MemberInitialization = enum {
    /// Do not write a default initializer (the current/previous behavior).
    none,
    /// Initialize members with `= undefined`.
    undefined,
    /// Initialize members with `= @import("std").mem.zeroes(T)`.
    zero,
};

pub fn parseFromArgs(args: []const [:0]const u8) !Options {
    var options: Options = undefined;

    const type_info = @typeInfo(Options).@"struct";
    var found_fields: [type_info.field_names.len]bool = @splat(false);
    inline for (type_info.field_names, type_info.field_types, 0..) |field_name, FieldType, field_index| {
        for (args) |arg| {
            const eq_pos = std.mem.find(u8, arg, "=") orelse continue;
            if (std.mem.eql(u8, arg[0..eq_pos], "--" ++ field_name)) {
                if (found_fields[field_index]) {
                    return error.DuplicateField;
                }

                const value = std.mem.trim(u8, arg[eq_pos + 1 ..], &std.ascii.whitespace);
                const field_value = try parseFieldFromArg(FieldType, value);
                @field(options, field_name) = field_value;
                found_fields[field_index] = true;
            }
        }
    }

    inline for (type_info.field_names, type_info.field_types, type_info.field_attrs, 0..) |field_name, FieldType, field_attr, field_index| {
        if (!found_fields[field_index]) {
            if (@typeInfo(FieldType) == .optional) {
                @field(options, field_name) = null;
                found_fields[field_index] = true;
            } else {
                if (field_attr.default_value_ptr != null) {
                    @field(options, field_name) = field_attr.defaultValue(FieldType) orelse unreachable;
                    found_fields[field_index] = true;
                } else {
                    std.log.err("Missing required field: {s}", .{field_name});
                    return error.MissingField;
                }
            }
        }
    }
    assert(std.mem.allEqual(bool, &found_fields, true));

    return options;
}

fn parseFieldFromArg(comptime T: type, value: []const u8) !T {
    switch (T) {
        []const u8, []u8 => return value,
        else => {},
    }
    const type_info = @typeInfo(T);
    switch (type_info) {
        .@"enum" => {
            return std.meta.stringToEnum(T, value) orelse {
                std.log.err("Invalid value for enum type: {s}", .{value});
                return error.InvalidFieldValue;
            };
        },
        .float => {
            return std.fmt.parseFloat(T, value);
        },
        .int => {
            return std.fmt.parseInt(T, value);
        },
        .bool => {
            if (std.mem.eql(u8, value, "true")) return true;
            if (std.mem.eql(u8, value, "false")) return false;
            std.log.err("Invalid value for bool type: {s}", .{value});
            return error.InvalidFieldValue;
        },
        .optional => |opt| {
            const ChildType = opt.child;
            if (std.mem.eql(u8, value, "null")) return null;
            return parseFieldFromArg(ChildType, value) orelse return error.InvalidFieldValue;
        },
        else => @compileError("Type: " ++ @typeName(T) ++ " is not supported for command line parsing."),
    }
}

pub fn format(self: Options, writer: *Io.Writer) void {
    writer.print("Options:\n", .{}) catch {};
    const type_info = @typeInfo(Options).@"struct";
    inline for (type_info.field_names, type_info.field_types) |field_name, FieldType| {
        switch (@typeInfo(FieldType)) {
            .pointer => writer.print("  --{s}={s}\n", .{ field_name, @field(self, field_name) }) catch {},
            .@"enum" => writer.print("  --{s}={s}\n", .{ field_name, @tagName(@field(self, field_name)) }) catch {},
            else => writer.print("  --{s}={}\n", .{ field_name, @field(self, field_name) }) catch {},
        }
    }
}

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;

test "member initialization option parses and formats" {
    const options = try Options.parseFromArgs(&.{
        "--interface_json=in.json",
        "--extension_api_json=extension_api.json",
        "--output_dir=out",
        "--builtin_build_conf=double_32",
        "--member_initialization=zero",
        "--strip_deprecation=true",
    });
    try std.testing.expectEqual(Options.MemberInitialization.zero, options.member_initialization);
    try std.testing.expectEqual(Options.BuiltinBuildConf.double_32, options.builtin_build_conf);
    try std.testing.expect(options.strip_deprecation);

    const default_options = try Options.parseFromArgs(&.{
        "--interface_json=in.json",
        "--extension_api_json=extension_api.json",
        "--output_dir=out",
    });
    try std.testing.expectEqual(Options.MemberInitialization.none, default_options.member_initialization);
    try std.testing.expectEqual(Options.BuiltinBuildConf.float_64, default_options.builtin_build_conf);

    // The formatted help must show the name the parser accepts, not `.zero`.
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    options.format(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "--member_initialization=zero") != null);
}
