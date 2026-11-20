//! Class registry: collects extension classes and registers them at the
//! configured engine initialization level.
//!
//! `Registry` is an optional convenience collector, not a requirement. The
//! individual registration helpers (`instance.zig`, `notification.zig`,
//! `ClassRegistration.zig`) are standalone and can be passed to
//! `classdb_register_extension_class6` directly.

classes: std.ArrayList(RegisteredClass) = .empty,
class_names: std.StringHashMapUnmanaged(void) = .empty,
arena: std.heap.ArenaAllocator,

const Registry = @This();

/// Compile-time options shared by every class in one `addClasses` group.
///
/// They are supplied with the call, not with the runtime `ClassRegistration`.
/// Both flags change callback shape and are passed as comptime parameters.
pub const ClassOptions = struct {
    /// When true, `OnReady` fields are initialized automatically once the node
    /// receives `NOTIFICATION_POST_ENTER_TREE`. The class must then declare a
    /// `Base` marker field; otherwise registration is a compile error.
    auto_onready: bool = false,
    /// When true, the free-instance callback runs
    /// `annotations.deinitPropertyFields` on the class's `Property` fields after
    /// the deinit callback. Off by default: property fields are user-managed.
    /// Passed to `FreeInstance` as a comptime parameter.
    auto_property_cleanup: bool = false,
    // TODO: `is_virtual` / `is_abstract` are future compile-time options. They
    // exist only once their callback behavior is implemented; they are not dead
    // runtime flags.
};

pub const ClassRegistration = @import("ClassRegistration.zig");
pub const virtuals = @import("virtuals.zig");

pub const RegisteredClass = struct {
    creation_info: interface.ClassCreationInfo6,
    /// Heap-stored `ClassRegistration` shared by the `addClasses` call that
    /// registered this class. Passed to the engine as `class_userdata`.
    data: *ClassRegistration,
    class_name: builtins.StringName, // static, no need to free/deinit
    parent_class_name: builtins.StringName, // static, no need to free/deinit
};

pub fn deinit(self: *Registry) void {
    self.arena.deinit();
    self.* = undefined;
}

/// `data.create_allocator` owner must out-live each class's "init"/"create" function call.
/// If a namespace is provided only the first level of public struct declarations is checked.
///
/// All classes in one call share `class_options` and one heap-stored
/// `ClassRegistration`. Use another call for a group with different options,
/// allocators, or registration level.
pub fn addClasses(
    self: *Registry,
    comptime p_classes: anytype,
    comptime class_options: ClassOptions,
    data: ClassRegistration,
) !void {
    const ClassesT = @TypeOf(p_classes);

    comptime if (!reflect.isTuple(ClassesT))
        @compileError("Please provide a comptime tuple of structs/namespace eg. .{ Class1, Class2 }. Found: " ++ @typeName(ClassesT));
    comptime if (p_classes.len == 0)
        @compileError("Please provide at least one class or namespace.");

    const p_registration = try self.arena.allocator().create(ClassRegistration);
    p_registration.* = data;

    @setEvalBranchQuota(50000);
    inline for (0..p_classes.len) |i| {
        const Class = p_classes[i];
        comptime if (@TypeOf(Class) != type) @compileError(std.fmt.comptimePrint(
            "At {} found '{s}', expected a type.",
            .{ i, @typeName(Class) },
        ));

        // Extension classes are checked first. `isLikelyNamespace` is only a
        // shape check (zero-field struct), so a valid zero-field extension class
        // stays an extension class; only the remaining shape is a namespace.
        if (comptime reflect.isExtensionClass(Class)) {
            try self.addClass(Class, Class.Extends, class_options, p_registration);
        } else if (comptime reflect.isLikelyNamespace(Class)) {
            try self.addClassesFromNamespace(Class, class_options, p_registration);
        } else {
            @compileError("'" ++ @typeName(Class) ++ "' must be an extension class (a struct declaring `Extends`) or a namespace struct of extension classes.");
        }
    }
}

// Namespace form: expand one level of public extension-class declarations.
fn addClassesFromNamespace(
    self: *Registry,
    comptime T: type,
    comptime class_options: ClassOptions,
    data: *ClassRegistration,
) !void {
    // `addClasses` only calls this for a type `reflect.isLikelyNamespace`
    // accepted, which already guarantees a zero-field struct.
    const struct_info = @typeInfo(T).@"struct";
    inline for (struct_info.decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime @TypeOf(Decl) == type and reflect.isExtensionClass(Decl)) {
            try self.addClass(Decl, Decl.Extends, class_options, data);
        }
    }
}

fn addClass(
    self: *Registry,
    comptime T: type,
    comptime Base: type,
    comptime class_options: ClassOptions,
    data: *ClassRegistration,
) !void {
    const c_class_name = comptime reflect.className(T);
    if (comptime reflect.isExtensionClass(Base)) {
        @compileError("Cannot register '" ++ @typeName(T) ++ "': Godot 4 does not support inheriting from another extension class ('" ++
            @typeName(Base) ++ "'). Use an engine class as the direct parent.");
    }
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

    const property_callbacks = property.callbacks(T);
    const class_creation_info: interface.ClassCreationInfo6 = .{
        .is_exposed = true,
        .create_instance_func = CreateInstance(T, Base),
        .free_instance_func = FreeInstance(T, Base, class_options.auto_property_cleanup),
        .get_virtual_func = get_virtual_func,
        .notification_func = Notification(T, Base, class_options.auto_onready),
        .set_func = property_callbacks.set_func,
        .get_func = property_callbacks.get_func,
        .get_property_list_func = property_callbacks.get_property_list_func,
        .free_property_list_func = property_callbacks.free_property_list_func,
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

comptime {
    // Keep the dynamic property backend's compile-only coverage analyzed even
    // when the example registers no property.
    property.comptimeSelfCheck();
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const reflect = @import("../reflect/reflect.zig");

const builtins = @import("../builtins/builtins.zig");

const property = @import("property.zig");

const CreateInstance = @import("instance.zig").CreateInstance;
const FreeInstance = @import("instance.zig").FreeInstance;
const Notification = @import("notification.zig").Notification;
