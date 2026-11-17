//! Class registry: collects extension classes and registers them at the
//! configured engine initialization level.
//!
//! `Registry` is an optional convenience collector, not a requirement. The
//! individual registration helpers (`instance.zig`, `notification.zig`,
//! `AddClassData.zig`) are standalone and can be passed to
//! `classdb_register_extension_class6` directly.

classes: std.ArrayList(ClassInfo) = .empty,
class_names: std.StringHashMapUnmanaged(void) = .empty,
arena: std.heap.ArenaAllocator,

pub const Registry = @This();

/// Compile-time options shared by every class in one `addClasses` group.
///
/// These change the shape of the runtime callbacks, so they are compile-time
/// values rather than fields of `AddClassData`.
pub const ClassOptions = struct {
    /// When true, `OnReady` fields are initialized automatically once the node
    /// receives `NOTIFICATION_POST_ENTER_TREE`. The class must then declare a
    /// `Base` marker field; otherwise registration is a compile error.
    auto_onready: bool = false,
    // TODO: `is_virtual` / `is_abstract` are future compile-time options. They
    // exist only once their callback behavior is implemented; they are not dead
    // runtime flags.
};

pub const AddClassData = @import("AddClassData.zig");
pub const virtuals = @import("virtuals.zig");

pub const ClassInfo = struct {
    creation_info: interface.ClassCreationInfo6,
    /// Heap-stored `AddClassData` shared by the `addClasses` call that
    /// registered this class. Passed to the engine as `class_userdata`.
    data: *AddClassData,
    class_name: builtins.StringName, // static, no need to free/deinit
    parent_class_name: builtins.StringName, // static, no need to free/deinit
};

pub fn deinit(self: *Registry) void {
    self.arena.deinit();
    self.* = undefined;
}

/// `data.create_allocator` owner must out-live each class's "init"/"create" function call.
/// If a namespace is provided only the first level of public struct decleration is checked.
///
/// All classes in one call share `class_options` and one heap-stored
/// `AddClassData`. Use another call for a group with different options,
/// allocators, or registration level.
pub fn addClasses(
    self: *Registry,
    comptime p_classes: anytype,
    comptime class_options: ClassOptions,
    data: AddClassData,
) !void {
    const ClassesT = @TypeOf(p_classes);

    comptime if (!reflect.isTuple(ClassesT))
        @compileError("Please provide a comptime tuple of structs/namespace eg. .{ Class1, Class2 }. Found: " ++ @typeName(ClassesT));
    comptime if (p_classes.len == 0)
        @compileError("Please provide at least one class or namespace.");

    const p_data = try self.arena.allocator().create(AddClassData);
    p_data.* = data;

    @setEvalBranchQuota(50000);
    inline for (0..p_classes.len) |i| {
        const Class = p_classes[i];
        comptime if (@TypeOf(Class) != type) @compileError(std.fmt.comptimePrint(
            "At {} found '{s}', expected a type.",
            .{ i, @typeName(Class) },
        ));

        const is_engine_class = comptime reflect.isEngineClass(Class);
        // A zero-field struct can be a valid extension class. Only a struct without
        // an engine base is a namespace.
        const is_likely_namespace = comptime reflect.isLikelyNamespace(Class) and !@hasDecl(Class, "Extends");
        if (!is_likely_namespace and !is_engine_class) {
            @compileError("'" ++ @typeName(Class) ++ "' does not an Extend an Engine class type.");
        }

        if (is_engine_class) {
            try self.addClass(Class, Class.Extends, class_options, p_data);
        } else if (is_likely_namespace) {
            try self.addClassesFromNamespace(Class, class_options, p_data);
        }
    }
}

// addClasses is enough.
fn addClassesFromNamespace(
    self: *Registry,
    comptime T: type,
    comptime class_options: ClassOptions,
    data: *AddClassData,
) !void {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("'" ++ @typeName(T) ++ "' is not a valid namespace.");
    const struct_info = type_info.@"struct";
    inline for (struct_info.decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime @TypeOf(Decl) == type and reflect.isEngineClass(Decl)) {
            try self.addClass(Decl, Decl.Extends, class_options, data);
        }
    }
}

// addClasses is enough.
fn addClass(
    self: *Registry,
    comptime T: type,
    comptime Base: type,
    comptime class_options: ClassOptions,
    data: *AddClassData,
) !void {
    const c_class_name = comptime reflect.className(T);
    const entry = try self.class_names.getOrPut(self.arena.allocator(), c_class_name);
    if (entry.found_existing) {
        std.log.err("'{s}' Class name is already in the registry.", .{c_class_name});
        return error.DuplicateClassName;
    }

    const class_name: builtins.StringName = .fromComptimeLatin1(c_class_name);
    const parent_class_name: builtins.StringName = .fromType(Base);

    const get_virtual_func = if (comptime @hasDecl(Base, "Virtual"))
        virtuals.getVirtual(T, Base)
    else
        null;

    const class_creation_info: interface.ClassCreationInfo6 = .{
        .is_exposed = true,
        .create_instance_func = CreateInstance(T, Base),
        .free_instance_func = FreeInstance(T, Base),
        .get_virtual_func = get_virtual_func,
        .notification_func = Notification(T, Base, class_options.auto_onready),
        .class_userdata = data,
    };

    const info = try self.classes.addOne(self.arena.allocator());
    info.* = .{
        .creation_info = class_creation_info,
        .data = data,
        .class_name = class_name,
        .parent_class_name = parent_class_name,
    };
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const reflect = @import("../reflect/reflect.zig");

const builtins = @import("../builtins/builtins.zig");

const CreateInstance = @import("instance.zig").CreateInstance;
const FreeInstance = @import("instance.zig").FreeInstance;
const Notification = @import("notification.zig").Notification;
