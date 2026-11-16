//! This works as a "registry" for classes to get registered on specific engine initialization point.
//!

classes: std.ArrayList(ClassInfo) = .empty,
class_names: std.StringHashMapUnmanaged(void) = .empty,
arena: std.heap.ArenaAllocator,

const Registry = @This();

pub const ClassInfo = struct {
    creation_info: interface.ClassCreationInfo6,
    options: *AddClassData,
    class_name: builtins.StringName, // static, no need to free/deinit
    parent_class_name: builtins.StringName, // static, no need to free/deinit
};

pub fn deinit(self: *Registry) void {
    self.arena.deinit();
    self.* = undefined;
}

/// `allocator` owner must out-live each class's "init"/"create" function call.
/// If namespace is provided only the first level of public struct decleration is checked.
pub fn addClasses(
    self: *Registry,
    comptime p_classes: anytype,
    options: AddClassData,
    comptime auto_onready: bool,
) !void {
    const ClassesT = @TypeOf(p_classes);

    comptime if (!auto.isTuple(ClassesT) and classesAsArray(p_classes).len == 0)
        @compileError("Please provide a comptime tuple of structs/namespace eg. .{ Class1, Class2 }. Found: " ++ @typeName(ClassesT));

    const p_options = try self.arena.allocator().create(AddClassData);
    p_options.* = options;

    @setEvalBranchQuota(50000);
    inline for (0..p_classes.len) |i| {
        const Class = p_classes[i];
        comptime if (@TypeOf(Class) != type) @compileError(std.fmt.comptimePrint(
            "At {} found '{s}', expected a type.",
            .{ i, @typeName(Class) },
        ));

        const is_engine_class = comptime auto.isEngineClass(Class);
        const is_namespace = comptime auto.isNamespace(Class);
        if (!is_namespace and !is_engine_class) {
            @compileError("'" ++ @typeName(Class) ++ "' does not an Extend an Engine class type.");
        }

        if (is_engine_class) {
            try self.addClass(Class, Class.Extends, p_options, auto_onready);
        } else if (is_namespace) {
            try self.addClassesFromNamespace(Class, p_options, auto_onready);
        }
    }
}

// addClasses is enough.
fn addClassesFromNamespace(
    self: *Registry,
    comptime T: type,
    options: *AddClassData,
    comptime auto_onready: bool,
) !void {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("'" ++ @typeName(T) ++ "' is not a valid namespace.");
    const struct_info = type_info.@"struct";
    inline for (struct_info.decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime @TypeOf(Decl) == type and auto.isEngineClass(Decl)) {
            try self.addClass(Decl, Decl.Extends, options, auto_onready);
        }
    }
}

const CreateInstance = @import("Registry/create_instance.zig").CreateInstance;
const Notification = @import("Registry/notification.zig").Notification;

// TODO: it's a duplicate from StringName, should we make it shared so StringName can use it too?
fn typeShortName(comptime T: type) [:0]const u8 {
    if (@hasDecl(T, "GodotClassName")) {
        return T.GodotClassName;
    }
    const full = @typeName(T);
    const pos = std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
    return full[pos + 1 ..];
}

fn checkVirtualMethodSignature(
    comptime method_name: [:0]const u8,
    comptime VirtualMethod: type,
    comptime DeclaredMethod: type,
) void {
    const VRetType = auto.FnReturnType(VirtualMethod) orelse void;
    const DRetType = auto.FnReturnType(DeclaredMethod) orelse void;
    if (VRetType != DRetType) {
        @compileError("The function signature doesn't match for " ++ method_name);
    }
    for (@typeInfo(VirtualMethod).@"fn".param_types, @typeInfo(DeclaredMethod).@"fn".param_types, 0..) |v_maybe_p, d_maybe_p, i| {
        const VP = v_maybe_p.?;
        const DP = d_maybe_p.?;
        if (i == 0) continue;

        if (VP != DP) {
            @compileError(std.fmt.comptimePrint(
                "The paremeter type at {} doesn't match, expected {s}, found {s}",
                .{ i, @typeName(VP), @typeName(DP) },
            ));
        }
    }
}

const VirtualMethodName = struct { zig: [:0]const u8, godot: [:0]const u8 };
fn collectVirtualMethods(comptime T: type, comptime Base: type) []const VirtualMethodName {
    return comptime blk: {
        const required_virts = std.meta.declarations(Base.Virtual.Required);
        const optional_virts = std.meta.declarations(Base.Virtual.Optional);
        var index = 0;
        var virtual_methods: [required_virts.len + optional_virts.len]VirtualMethodName = undefined;
        for (required_virts) |required_virt| {
            if (!@hasDecl(T, required_virt))
                @compileError("Type '" ++ @typeName(T) ++ "' doesn't have required virtual method: " ++ required_virt);
            const VirtMethod = std.meta.Child(@field(Base.Virtual.Required, required_virt));
            const DeclaredMethod = @TypeOf(@field(T, required_virt));
            checkVirtualMethodSignature(required_virt, VirtMethod, DeclaredMethod);

            virtual_methods[index] = .{
                .zig = required_virt,
                .optional_virt = runtime.naming.comptimeConvert(.godot, .virtual_method, required_virt),
            };
            index += 1;
        }
        for (optional_virts) |optional_virt| {
            if (@hasDecl(T, optional_virt)) {
                const VirtMethod = std.meta.Child(@field(Base.Virtual.Required, optional_virt));
                const DeclaredMethod = @TypeOf(@field(T, optional_virt));
                checkVirtualMethodSignature(optional_virt, VirtMethod, DeclaredMethod);

                virtual_methods[index] = .{
                    .zig = optional_virt,
                    .godot = runtime.naming.comptimeConvert(.godot, .virtual_method, optional_virt),
                };
                index += 1;
            }
        }

        break :blk virtual_methods[0..index];
    };
}

// addClasses is enough.
fn addClass(
    self: *Registry,
    comptime T: type,
    comptime Base: type,
    options: *AddClassData,
    comptime auto_onready: bool,
) !void {
    const c_class_name = comptime typeShortName(T);
    const entry = try self.class_names.getOrPut(self.arena.allocator(), c_class_name);
    if (entry.found_existing) {
        std.log.err("'{s}' Class name is already in the registry.", .{c_class_name});
        return error.DuplicateClassName;
    }

    const class_name: builtins.StringName = .fromComptimeLatin1(c_class_name);
    const parent_class_name: builtins.StringName = .fromType(Base);

    const class_creation_info: interface.ClassCreationInfo6 = .{
        .is_exposed = true,
        .create_instance_func = CreateInstance(T, Base),
        .free_instance_func = &struct {
            fn f(userdata: ?*anyopaque, p_instance: interface.ClassInstancePtr) callconv(.c) void {
                const p_options: *AddClassData = @ptrCast(@alignCast(userdata orelse return));
                const instance: *T = @ptrCast(@alignCast(p_instance));
                auto.annot.callDeinitCallback(T, Base, instance, p_options.gpa orelse p_options.create_allocator);
                return p_options.create_allocator.destroy(instance);
            }
        }.f,
        .get_virtual_func = &struct {
            fn f(_: ?*anyopaque, p_name: interface.ConstStringNamePtr, p_hash: u32) callconv(.c) interface.ClassCallVirtual {
                @setRuntimeSafety(false);
                const p_method_name: *const builtins.StringName = @ptrCast(@alignCast(p_name orelse return null));

                var buffer = p_method_name.toAsciiBuffer();
                defer buffer.deinit();
                const as_bytes = buffer.bytesConst();

                std.log.debug("{s} Was looking for: {s}", .{ @typeName(T), as_bytes });

                const ready_method_name: builtins.StringName = .fromComptimeLatin1("_ready");
                if (!ready_method_name.opEqlStringName(p_method_name)) return null;
                if (p_hash != 3218959716) return null;
                return &struct {
                    fn f(p_instance: interface.ClassInstancePtr, _: [*c]const interface.ConstTypePtr, _: interface.TypePtr) callconv(.c) void {
                        const instance: *T = @ptrCast(@alignCast(p_instance));
                        instance._ready();
                    }
                }.f;
            }
        }.f,
        .notification_func = Notification(T, Base, auto_onready),
        .class_userdata = options,
    };

    const info = try self.classes.addOne(self.arena.allocator());
    info.* = .{
        .creation_info = class_creation_info,
        .options = options,
        .class_name = class_name,
        .parent_class_name = parent_class_name,
    };

    std.debug.print("Added register queue: {s}\n", .{@typeName(T)});
}

inline fn classesAsArray(comptime p_classes: anytype) []const type {
    return @as([]const type, p_classes);
}

pub const AddClassData = @import("Registry/AddClassData.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings");
const interface = bindings.interface;

const auto = @import("auto/auto.zig");

const builtins = @import("builtins/builtins.zig");
const classes_mod = @import("classes/classes.zig");

const runtime = @import("godot.zig");
