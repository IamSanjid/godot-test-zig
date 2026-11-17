//! Metadata-driven virtual method registration.
//!
//! The generated class exposes `Virtual.Required`, `Virtual.Optional` and
//! `Virtual.Meta`. User classes declare ordinary Zig methods with the generated
//! virtual signature; this module supplies the C callback.

pub const Entry = struct {
    /// Declaration name on the user class.
    name: [:0]const u8,
    /// Engine-facing virtual name.
    godot_name: [:0]const u8,
    hash: u32,
    callback: interface.ClassCallVirtual,
};

/// Collect the virtuals declared by `T` for `Base`.
///
/// Required virtuals must be declared. Optional virtuals are included only when
/// declared. The result is a comptime slice of specialized callbacks.
pub fn collect(comptime T: type, comptime Base: type) []const Entry {
    const override_decls = override.findOverrideDecls(T);
    const meta_decls = std.meta.declarations(Base.Virtual.Meta);

    var entries: [meta_decls.len]Entry = undefined;
    var count: usize = 0;

    inline for (meta_decls) |name| {
        const meta = @field(Base.Virtual.Meta, name);
        const godot_name = meta.godot_name;

        const is_required = @hasDecl(Base.Virtual.Required, name);
        const is_optional = @hasDecl(Base.Virtual.Optional, name);
        if (comptime is_required == is_optional) {
            @compileError("Virtual '" ++ name ++ "' must be in exactly one of Virtual.Required or Virtual.Optional.");
        }

        const declared = @hasDecl(T, name) or override_decls.has(godot_name);
        if (comptime is_required and !declared) {
            @compileError("Type '" ++ @typeName(T) ++ "' is missing required virtual '" ++ name ++ "'.");
        }
        if (!declared) continue;

        const declaredFn = if (override_decls.get(godot_name)) |decl_name|
            @field(T, decl_name).override_with
        else
            @field(T, name);
        const VirtualFn = std.meta.Child(if (is_required)
            @field(Base.Virtual.Required, name)
        else
            @field(Base.Virtual.Optional, name));

        validateSignature(T, name, meta.static, VirtualFn, @TypeOf(declaredFn));

        entries[count] = .{
            .name = name,
            .godot_name = godot_name,
            .hash = meta.hash,
            .callback = makeCallback(declaredFn, meta),
        };
        count += 1;
    }

    return entries[0..count];
}

/// Build the `get_virtual_func` callback for a class.
pub fn getVirtual(comptime T: type, comptime Base: type) interface.ClassGetVirtual2 {
    return &struct {
        fn get(
            _: ?*anyopaque,
            p_name: interface.ConstStringNamePtr,
            p_hash: u32,
        ) callconv(.c) interface.ClassCallVirtual {
            const entries = comptime collect(T, Base);
            if (p_name == null) return null;

            const name: *const builtins.StringName = @ptrCast(@alignCast(p_name.?));
            inline for (entries) |entry| {
                if (p_hash == 0 or p_hash == entry.hash) {
                    if (name.opEqlStringName(&builtins.StringName.fromComptimeLatin1(entry.godot_name))) {
                        return entry.callback;
                    }
                }
            }
            return null;
        }
    }.get;
}

fn validateSignature(
    comptime T: type,
    comptime name: []const u8,
    comptime is_static: bool,
    comptime VirtualFn: type,
    comptime DeclaredFn: type,
) void {
    const virtual_info = switch (@typeInfo(VirtualFn)) {
        .@"fn" => |info| info,
        else => @compileError("Generated virtual '" ++ name ++ "' is not a function."),
    };
    const declared_info = switch (@typeInfo(DeclaredFn)) {
        .@"fn" => |info| info,
        else => @compileError("Declared virtual '" ++ name ++ "' is not a function."),
    };

    if (declared_info.is_generic) {
        @compileError("Declared virtual '" ++ name ++ "' must not be generic.");
    }
    if (declared_info.param_types.len != virtual_info.param_types.len) {
        @compileError("Declared virtual '" ++ name ++ "' has the wrong parameter count.");
    }

    const offset: usize = if (is_static) 0 else 1;
    if (!is_static) {
        const Self = declared_info.param_types[0] orelse
            @compileError("Declared virtual '" ++ name ++ "' is missing its self parameter.");
        const self_info = switch (@typeInfo(Self)) {
            .pointer => |info| info,
            else => @compileError("Declared virtual '" ++ name ++ "' self parameter must be a pointer."),
        };
        if (self_info.child != T) {
            @compileError("Declared virtual '" ++ name ++ "' self parameter must point to " ++ @typeName(T) ++ ".");
        }
    }

    for (declared_info.param_types[offset..], virtual_info.param_types[offset..]) |declared, virtual| {
        if (declared != virtual) {
            @compileError(std.fmt.comptimePrint(
                "Declared virtual '{s}' parameter type mismatch.",
                .{name},
            ));
        }
    }
    if (declared_info.return_type != virtual_info.return_type) {
        @compileError("Declared virtual '" ++ name ++ "' return type mismatch.");
    }
}

fn makeCallback(
    comptime declaredFn: anytype,
    comptime meta: anytype,
) interface.ClassCallVirtual {
    const DeclaredFn = @TypeOf(declaredFn);
    return &struct {
        fn call(
            p_instance: interface.ClassInstancePtr,
            p_args: [*c]const interface.ConstTypePtr,
            r_ret: interface.TypePtr,
        ) callconv(.c) void {
            const info = @typeInfo(DeclaredFn).@"fn";
            var args: std.meta.ArgsTuple(DeclaredFn) = undefined;

            if (comptime !meta.static) {
                args[0] = @ptrCast(@alignCast(p_instance));
            }

            const offset: usize = if (meta.static) 0 else 1;
            inline for (info.param_types[offset..], 0..) |maybe_param, index| {
                const Param = maybe_param.?;
                args[offset + index] = readArgument(Param, p_args[index]);
            }

            const result = @call(.auto, declaredFn, args);

            const Return = info.return_type orelse void;
            if (comptime Return != void) {
                writeReturn(Return, result, r_ret);
            }
        }
    }.call;
}

fn readArgument(comptime Param: type, ptr: interface.ConstTypePtr) Param {
    if (comptime reflect.isRefCountedPointer(Param)) {
        const ref: interface.ConstRefPtr = @ptrCast(@alignCast(ptr));
        const object = runtime.dispatch(.ref_get_object, .{ref});

        if (comptime reflect.isOptionalPointer(Param)) {
            return if (object) |value| @ptrCast(value) else null;
        }
        return @ptrCast(object orelse @panic("Godot passed a null RefCounted object for a non-optional virtual argument"));
    }

    return abi.readArgument(Param, @ptrCast(ptr));
}

fn writeReturn(comptime Return: type, value: Return, ptr: interface.TypePtr) void {
    if (comptime reflect.isRefCountedPointer(Return)) {
        const object: interface.ObjectPtr = if (comptime reflect.isOptionalPointer(Return))
            if (value) |item| @ptrCast(item) else null
        else
            @ptrCast(value);

        runtime.dispatch(.ref_set_object, .{
            @as(interface.RefPtr, @ptrCast(@alignCast(ptr))),
            object,
        });
        return;
    }

    abi.writeReturn(Return, @ptrCast(ptr), value);
}

const std = @import("std");
const bindings = @import("bindings");
const builtins = @import("../builtins/builtins.zig");
const reflect = @import("../reflect/reflect.zig");
const abi = @import("../abi.zig");

const runtime = @import("../runtime.zig");

const override = @import("../annotations/override.zig");

const interface = bindings.interface;
