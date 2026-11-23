//! Compile-only coverage for engine/extension class classification and object
//! pointer predicates on `godot.reflect`.
//!
//! Fake extension classes sit on real engine classes. The fakes classify types
//! only: extension -> engine base resolution (and the Base markers it requires)
//! is covered by the `extension.zig` tests.

const EngineObject = classes.core.Object;
const EngineNode = classes.core.Node;
const EngineNode2D = classes.core.Node2D;
const EngineResource = classes.core.Resource;
const EngineTexture2D = classes.core.Texture2D;

/// Direct extension class over an engine class; no Base marker needed to be
/// classified as an extension class.
const DirectExtension = struct {
    pub const Extends = EngineNode;
};

/// Extension class whose `Extends` is another extension class.
const ChainedExtension = struct {
    pub const Extends = DirectExtension;
    value: u32 = 0,
};

/// Zero-field extension declarations are valid extension classes.
const ZeroFieldExtension = struct {
    pub const Extends = EngineNode;
};

/// Extension class over a RefCounted descendant.
const RefCountedExtension = struct {
    pub const Extends = classes.core.RefCounted;
};

/// Extension class over a Resource descendant.
const ResourceExtension = struct {
    pub const Extends = EngineResource;
};

/// Extension class over Object that is neither a Node nor a Resource.
const ObjectExtension = struct {
    pub const Extends = EngineObject;
};

const NotAClass = struct {
    value: u32 = 0,
};

const NotAClassEnum = enum { a, b };

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("reflect.objects: " ++ message);
}

fn comptimeChecks() void {
    check(reflect.isEngineObjectClass(EngineObject), "classes.core.Object must be an engine object class");
    check(reflect.isEngineObjectClass(EngineNode), "classes.core.Node must be an engine object class");
    check(!reflect.isEngineObjectClass(DirectExtension), "an extension class is not an engine object class");
    check(!reflect.isEngineObjectClass(NotAClass), "a plain struct is not an engine object class");
    check(!reflect.isEngineObjectClass(u32), "a scalar is not an engine object class");

    check(reflect.isExtensionClass(DirectExtension), "a struct extending an engine class is an extension class");
    check(reflect.isExtensionClass(ChainedExtension), "extension -> extension chains are extension classes");
    check(reflect.isExtensionClass(ZeroFieldExtension), "zero-field extension classes are extension classes");
    check(reflect.isExtensionClass(RefCountedExtension), "extension classes may extend any engine object class");
    check(!reflect.isExtensionClass(EngineNode), "engine object classes are not extension classes");
    check(!reflect.isExtensionClass(NotAClass), "a struct without Extends is not an extension class");
    check(!reflect.isExtensionClass(u32), "a scalar is not an extension class");

    check(reflect.isClassType(EngineObject) and reflect.isClassType(EngineNode), "engine object classes are class types");
    check(reflect.isClassType(DirectExtension) and reflect.isClassType(ChainedExtension) and reflect.isClassType(ZeroFieldExtension), "extension classes are class types");
    check(!reflect.isClassType(u32) and !reflect.isClassType(NotAClass), "non-class types are not class types");

    check(reflect.isNodeClass(EngineNode), "Node is a Node class");
    check(reflect.isNodeClass(EngineNode2D), "Node2D inherits Node through CanvasItem");
    check(reflect.isNodeClass(DirectExtension), "an extension class over Node is a Node class");
    check(reflect.isNodeClass(ChainedExtension), "extension -> extension chains over Node are Node classes");
    check(!reflect.isNodeClass(EngineObject), "Object does not inherit Node");
    check(!reflect.isNodeClass(classes.core.RefCounted), "RefCounted does not inherit Node");
    check(!reflect.isNodeClass(EngineResource), "Resource does not inherit Node");
    check(!reflect.isNodeClass(EngineTexture2D), "Texture2D does not inherit Node");
    check(!reflect.isNodeClass(ObjectExtension), "an extension class over Object is not a Node class");
    check(!reflect.isNodeClass(RefCountedExtension), "an extension class over RefCounted is not a Node class");
    check(!reflect.isNodeClass(NotAClass), "a plain struct is not a Node class");
    check(!reflect.isNodeClass(NotAClassEnum), "an enum is not a Node class");
    check(!reflect.isNodeClass(u32), "a scalar is not a Node class");
    check(!reflect.isNodeClass(*EngineNode), "an object pointer is not a Node class");

    check(reflect.isResourceClass(EngineResource), "Resource is a Resource class");
    check(reflect.isResourceClass(EngineTexture2D), "Texture2D inherits Resource through Texture");
    check(reflect.isResourceClass(ResourceExtension), "an extension class over Resource is a Resource class");
    check(!reflect.isResourceClass(RefCountedExtension), "an extension class over RefCounted is not a Resource class");
    check(!reflect.isResourceClass(EngineObject), "Object does not inherit Resource");
    check(!reflect.isResourceClass(classes.core.RefCounted), "RefCounted does not inherit Resource");
    check(!reflect.isResourceClass(EngineNode), "Node does not inherit Resource");
    check(!reflect.isResourceClass(EngineNode2D), "Node2D does not inherit Resource");
    check(!reflect.isResourceClass(ObjectExtension), "an extension class over Object is not a Resource class");
    check(!reflect.isResourceClass(NotAClass), "a plain struct is not a Resource class");
    check(!reflect.isResourceClass(NotAClassEnum), "an enum is not a Resource class");
    check(!reflect.isResourceClass(u32), "a scalar is not a Resource class");
    check(!reflect.isResourceClass(*EngineResource), "an object pointer is not a Resource class");

    check(reflect.isRefCounted(classes.core.RefCounted), "RefCounted is refcounted");
    check(!reflect.isRefCounted(EngineObject), "Object is not refcounted");
    check(!reflect.isRefCounted(EngineNode), "Node is not refcounted");
    check(reflect.isRefCounted(RefCountedExtension), "an extension class over RefCounted is refcounted");
    check(!reflect.isRefCounted(DirectExtension), "an extension class over Node is not refcounted");
    check(!reflect.isRefCounted(u32), "a scalar is not refcounted");

    check(reflect.isRefCountedPointer(*classes.core.RefCounted), "*RefCounted is a refcounted pointer");
    check(reflect.isRefCountedPointer(?*const classes.core.RefCounted), "?*const RefCounted is a refcounted pointer");
    check(reflect.isRefCountedPointer(*const RefCountedExtension), "*RefCountedExtension is a refcounted pointer");
    check(!reflect.isRefCountedPointer(classes.core.RefCounted), "a class value is not a refcounted pointer");
    check(!reflect.isRefCountedPointer(*EngineNode), "an Object/Node pointer is not refcounted");
    check(!reflect.isRefCountedPointer(*DirectExtension), "an extension over Node is not refcounted");
    check(!reflect.isRefCountedPointer([2]*classes.core.RefCounted), "an array of RefCounted pointers is not a refcounted pointer");
    check(!reflect.isRefCountedPointer([*]*classes.core.RefCounted), "a many-pointer to RefCounted pointers is not a refcounted pointer");
    check(!reflect.isRefCountedPointer([]*classes.core.RefCounted), "a slice of RefCounted pointers is not a refcounted pointer");
    check(!reflect.isRefCountedPointer(?[*]*classes.core.RefCounted), "an optional many-pointer is not a refcounted pointer");
    check(!reflect.isRefCountedPointer(*u32), "a scalar pointer is not a refcounted pointer");
    check(!reflect.isRefCountedPointer(u32), "a scalar is not a refcounted pointer");

    {
        const target = reflect.objectTarget(*EngineNode);
        check(target != null, "*EngineNode must be an object pointer");
        check(target.?.class == EngineNode, "objectTarget must report the pointee class");
        check(target.?.kind == .engine, "*EngineNode must be reported as engine kind");
        check(!target.?.optional and !target.?.is_const, "*EngineNode is a mutable non-optional pointer");
    }
    {
        const target = reflect.objectTarget(?*const EngineNode);
        check(target != null, "?*const EngineNode must be an object pointer");
        check(target.?.kind == .engine, "?*const EngineNode must be reported as engine kind");
        check(target.?.optional and target.?.is_const, "?*const EngineNode is an optional const pointer");
    }
    {
        const target = reflect.objectTarget(*DirectExtension);
        check(target != null, "*Extension must be an object pointer");
        check(target.?.kind == .extension, "extension pointers must be reported as extension kind");
        check(target.?.class == DirectExtension, "objectTarget must report the extension class");
    }
    check(reflect.objectTarget(ChainedExtension) == null, "class values are not object pointers");
    check(reflect.objectTarget(*u32) == null, "scalar pointers are not object pointers");
    check(reflect.objectTarget(*anyopaque) == null and reflect.objectTarget(?*const anyopaque) == null, "anyopaque pointers are not object pointers");
    check(reflect.objectTarget([*]DirectExtension) == null and reflect.objectTarget([]DirectExtension) == null, "many pointers and slices are not object pointers");
    check(reflect.objectTarget(?[*]const DirectExtension) == null, "optional many pointers are not object pointers");
    check(reflect.objectClassOf(?*ChainedExtension) == ChainedExtension, "objectClassOf unwraps optional pointers");
    check(reflect.objectClassOf(*u32) == null, "objectClassOf returns null for non-class pointers");
    check(reflect.isObjectPointer(*EngineNode) and reflect.isObjectPointer(?*ChainedExtension), "isObjectPointer accepts class pointers");
    check(!reflect.isObjectPointer(usize) and !reflect.isObjectPointer(EngineNode), "isObjectPointer rejects non-pointers");
}

comptime {
    comptimeChecks();
}

test "object class reflection" {
    comptime comptimeChecks();
}

const godot = @import("godot");
const classes = godot.classes;
const reflect = godot.reflect;
