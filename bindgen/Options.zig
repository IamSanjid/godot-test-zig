interface_json: []const u8,
output_dir: []const u8,

const Options = @This();

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

    inline for (type_info.field_names, type_info.field_types, 0..) |field_name, FieldType, field_index| {
        if (!found_fields[field_index]) {
            if (@typeInfo(FieldType) == .optional) {
                @field(options, field_name) = null;
                found_fields[field_index] = true;
            } else {
                std.log.err("Missing required field: {s}", .{field_name});
                return error.MissingField;
            }
        }
    }

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
        switch (FieldType) {
            []const u8, []u8 => {
                writer.print("  --{s}={s}\n", .{ field_name, @field(self, field_name) }) catch {};
            },
            else => {
                writer.print("  --{s}={}\n", .{ field_name, @field(self, field_name) }) catch {};
            },
        }
    }
}

const std = @import("std");
const Io = std.Io;
