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
    /// Expose the class in ClassDB and editor listings.
    is_exposed: bool = true,
    /// In the editor the engine builds a placeholder from the native base instead
    /// of the extension instance, so extension code does not run there.
    is_runtime: bool = true,
    /// Editor class icon path.
    icon_path: ?[:0]const u8 = null,
    /// Hides the class from editor creation dialogs, the resource picker, and
    /// docs while keeping it instantiable; requires `is_exposed = true` and
    /// changes no callback.
    is_virtual: bool = false,
    /// Namespace nesting depth to expand; 1 registers direct extension classes
    /// only, 2 also descends one namespace level.
    depth: u8 = 2,
    // TODO: `is_abstract` (no instance creation) is not implemented; see docs/classdb.md.
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
    /// Null when the class declares no class-level metadata.
    post_registration_callback: ?classdb.PostRegistrationCallback,
};

pub fn deinit(self: *Registry) void {
    self.arena.deinit();
    self.* = undefined;
}

/// The group's `instance_allocator`/`gpa` must out-live all instances and callbacks.
/// A namespace scans only its first level of public struct declarations.
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

    const IconPathStorage = struct {
        var value: builtins.String = undefined;
        var initialized: bool = false;
    };
    const icon_path: ?*const builtins.String = blk: {
        if (comptime class_options.icon_path) |path_str| {
            if (!IconPathStorage.initialized) {
                IconPathStorage.value = .fromComptimeLatin1(path_str);
                IconPathStorage.initialized = true;
            }
            break :blk &IconPathStorage.value;
        }
        break :blk null;
    };

    if (comptime class_options.depth == 0) @compileError("ClassOptions.depth must be at least 1.");
    comptime if (class_options.is_virtual and !class_options.is_exposed)
        @compileError("ClassOptions.is_virtual requires is_exposed = true: ClassDB::is_virtual() " ++
            "checks can_instantiate(), which requires an exposed class.");
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
            try self.addClass(Class, Class.Extends, class_options, p_registration, icon_path);
        } else if (comptime reflect.isLikelyNamespace(Class)) {
            try self.addClassesFromNamespace(
                Class,
                class_options,
                p_registration,
                icon_path,
                class_options.depth,
            );
        } else {
            @compileError("'" ++ @typeName(Class) ++ "' must be an extension class (a struct declaring `Extends`) or a namespace struct of extension classes.");
        }
    }
}

// Namespace form: expand public types up to `depth`.
fn addClassesFromNamespace(
    self: *Registry,
    comptime T: type,
    comptime class_options: ClassOptions,
    data: *ClassRegistration,
    icon_path: ?*const builtins.String,
    comptime depth: u8,
) !void {
    // `addClasses` only calls this for a type `reflect.isLikelyNamespace`
    // accepted, which already guarantees a zero-field struct.
    const struct_info = @typeInfo(T).@"struct";
    inline for (struct_info.decl_names) |decl_name| {
        const Decl = @field(T, decl_name);
        if (comptime @TypeOf(Decl) != type) continue;
        if (comptime reflect.isExtensionClass(Decl)) {
            try self.addClass(Decl, Decl.Extends, class_options, data, icon_path);
        } else if (comptime depth > 1 and reflect.isLikelyNamespace(Decl)) {
            try self.addClassesFromNamespace(Decl, class_options, data, icon_path, depth - 1);
        }
    }
}

fn addClass(
    self: *Registry,
    comptime T: type,
    comptime Base: type,
    comptime class_options: ClassOptions,
    data: *ClassRegistration,
    icon_path: ?*const builtins.String,
) !void {
    const c_class_name = comptime reflect.className(T);
    if (comptime reflect.isExtensionClass(Base)) {
        @compileError("Cannot register '" ++ @typeName(T) ++ "': Godot 4 does not support inheriting from another extension class ('" ++
            @typeName(Base) ++ "'). Use an engine class as the direct parent.");
    }
    const entry = try self.class_names.getOrPut(self.arena.allocator(), c_class_name);
    if (entry.found_existing) {
        std.log.err(
            "Class name '{s}' is already registered by '{s}'. Set a distinct `pub const GodotClassName` on one class.",
            .{ c_class_name, @typeName(T) },
        );
        return error.DuplicateClassName;
    }

    const class_name: builtins.StringName = .fromLatin1(c_class_name, true);
    const parent_class_name: builtins.StringName = .fromType(Base);

    const get_virtual_func = if (comptime @hasDecl(Base, "Virtual"))
        virtuals.getVirtual(T, Base)
    else
        null;

    const property_callbacks = property.callbacks(T);
    const class_creation_info: interface.ClassCreationInfo6 = .{
        .is_virtual = class_options.is_virtual,
        .is_exposed = class_options.is_exposed,
        .is_runtime = class_options.is_runtime,
        .icon_path = icon_path,
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
        .post_registration_callback = classdb.postRegistrationCallback(T),
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
const classdb = @import("classdb.zig");

const CreateInstance = @import("instance.zig").CreateInstance;
const FreeInstance = @import("instance.zig").FreeInstance;
const Notification = @import("notification.zig").Notification;
