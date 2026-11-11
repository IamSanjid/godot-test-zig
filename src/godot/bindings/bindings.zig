pub fn Dispatcher(comptime procs_tags: []const interface.ProcsTag) type {
    const tags_type_info = @typeInfo(interface.ProcsTag).@"enum";

    const ProcsT = if (procs_tags.len == 0) blk: {
        var field_types: [tags_type_info.field_names.len]type = undefined;
        for (tags_type_info.field_names, 0..) |field_name, i| {
            field_types[i] = @field(interface.ProcsTypes, field_name);
        }

        break :blk @Struct(.auto, null, tags_type_info.field_names, &field_types, &@splat(.{}));
    } else blk: {
        var field_types: [procs_tags.len]type = undefined;
        for (procs_tags, 0..) |proc, i| {
            field_types[i] = @field(interface.ProcsTypes, @tagName(proc));
        }

        break :blk @Struct(.auto, null, tags_type_info.field_names, field_types, &@splat(.{}));
    };

    return struct {
        library: interface.ClassLibraryPtr,
        procs: Procs,

        const Self = @This();
        pub const Procs = ProcsT;
        pub const Diagnostics = struct {
            function: [64]u8 = @splat(0),

            pub const Where = struct {
                function: ?[]const u8,
            };

            pub fn fail(maybe_diags: ?*Diagnostics, where: Where, err: anyerror) anyerror {
                const diags = maybe_diags orelse return err;
                if (where.function) |f| @memcpy(&diags.function, f);
                return err;
            }

            pub fn format(self: Diagnostics, writer: *std.Io.Writer) !void {
                try writer.print("Function: {s}", .{self.function});
            }
        };

        pub fn init(
            getProcAddress: Child(interface.InterfaceGetProcAddress),
            library: interface.ClassLibraryPtr,
            diags: ?*Diagnostics,
        ) !Self {
            var procs: Procs = undefined;
            if (procs_tags.len == 0) {
                inline for (tags_type_info.field_names) |proc| {
                    @field(procs, proc) = @ptrCast(getProcAddress(proc) orelse
                        return Diagnostics.fail(diags, .{ .function = proc }, error.InterfaceFunctionNotFound));
                }
            } else {
                for (procs_tags) |proc| {
                    @field(procs, @tagName(proc)) = @ptrCast(getProcAddress(@tagName(proc)) orelse
                        return Diagnostics.fail(diags, .{ .function = proc }, error.InterfaceFunctionNotFound));
                }
            }

            return .{ .library = library, .procs = procs };
        }

        pub fn ProcReturnAddress(comptime proc: interface.ProcsTag) type {
            if (!@hasField(Procs, @tagName(proc)))
                @compileError("The specified Proc is not part of this Dispatcher type, " ++
                    "consider adding it to the array when creating the Dispatcher type.");

            const ProcPtrType = @field(interface.ProcsTypes, @tagName(proc));
            const ProcType = @typeInfo(ProcPtrType).pointer.child;
            return @typeInfo(ProcType).@"fn".return_type orelse void;
        }

        pub fn ProcArgumentTypesAsTuple(comptime proc: interface.ProcsTag) type {
            if (!@hasField(Procs, @tagName(proc)))
                @compileError("The specified Proc is not part of this Dispatcher type, " ++
                    "consider adding it to the array when creating the Dispatcher type.");

            const ProcPtrType = @field(interface.ProcsTypes, @tagName(proc));
            const ProcType = @typeInfo(ProcPtrType).pointer.child;
            const fn_type = @typeInfo(ProcType).@"fn";

            var tuple_types: [fn_type.param_types.len]type = undefined;
            for (fn_type.param_types, 0..) |pt, i| {
                tuple_types[i] = pt orelse
                    @compileError("Parameter Type needs well defined type but found null for " ++ @tagName(proc) ++ ", param no: " ++ i);
            }

            return @Tuple(&tuple_types);
        }

        pub fn dispatch(
            self: *const Self,
            comptime proc: interface.ProcsTag,
            args: ProcArgumentTypesAsTuple(proc),
        ) ProcReturnAddress(proc) {
            const proc_ptr = @field(self.procs, @tagName(proc));
            return @call(.auto, proc_ptr, args);
        }
    };
}

const std = @import("std");
const Child = std.meta.Child;

pub const builtins = @import("builtins/builtins.zig");
pub const classes = @import("classes/classes.zig");
pub const constants = @import("constants.zig");
pub const enums = @import("enums.zig");
pub const interface = @import("interface.zig");
pub const native = @import("native.zig");
pub const singletons = @import("singletons.zig");
pub const utility = @import("utility/utility.zig");

pub const is_double_precision = @sizeOf(builtins.Variant) == 40;
