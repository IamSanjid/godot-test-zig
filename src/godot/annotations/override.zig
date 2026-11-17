pub fn Override(comptime virtual_method: [:0]const u8, comptime with: anytype) type {
    if (!reflect.isFn(with)) @compileError("The override `with` is not a method.");
    if (!reflect.isNormalFunction(with)) @compileError("The override `with` is not a normal runtime dispatchable method.");

    return struct {
        pub const godot_virtual_method = virtual_method;
        pub const override_with = with;
    };
}

pub fn findOverrideDecls(comptime T: type) std.StaticStringMap([:0]const u8) {
    return blk: {
        const decls = std.meta.declarations(T);
        var decl_names: [decls.len][:0]const u8 = undefined;
        var count = 0;
        for (decls) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type) continue;
            if (!isOverride(Decl)) continue;
            decl_names[count] = decl_name;
            count += 1;
        }

        const TupleElement = struct { [:0]const u8, [:0]const u8 };
        const tuple_types: [count]type = @splat(TupleElement);
        const TupleType = @Tuple(&tuple_types);
        var args: TupleType = undefined;
        for (decl_names[0..count], 0..) |decl_name, i| {
            const Decl = @field(T, decl_name);
            args[i] = .{ Decl.godot_virtual_method, decl_name };
        }

        break :blk std.StaticStringMap([:0]const u8).initComptime(args);
    };
}

fn isOverride(comptime T: type) bool {
    if (!@hasDecl(T, "godot_virtual_method") or
        !@hasDecl(T, "override_with")) return false;
    return T == Override(T.godot_virtual_method, T.override_with);
}

const std = @import("std");

const reflect = @import("../reflect/reflect.zig");
