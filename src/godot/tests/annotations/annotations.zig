//! Facade-level integration of annotation field initialization.
//!
//! Compile-only coverage: annotation field initialization must only touch
//! OnReady fields, and the exported `.read_only` / `.init` API must compose
//! through the `godot.annotations` facade.

// Mixed annotation kinds must not cross-classify fields.
const MixedFieldOwner = struct {
    node: godot.annotations.OnReady(godot.classes.core.Node).Node("./ChildNode"),
    health: godot.annotations.Property(i32, .{ .usage = .exported }) = .init(0),
};

fn checkMixedFieldOwner() void {
    if (comptime godot.annotations.findOnReadyFieldNames(MixedFieldOwner).len != 1)
        @compileError("initAnnotFieldsDefault must not treat Property fields as OnReady fields");
    var owner: MixedFieldOwner = .{ .node = .{} };
    var dummy_base: void = {};
    godot.annotations.initAnnotFieldsDefault(MixedFieldOwner, void, &owner, &dummy_base);
    if (owner.node.value != null) @compileError("initAnnotFieldsDefault must initialize OnReady fields");
    if (owner.health.value != 0) @compileError("initAnnotFieldsDefault must not touch Property fields");
}

fn five() u32 {
    return 5;
}

// The exported `.read_only` / `.init` API composes through the annotations
// facade, including eager initializer assignment and read-only dispatch policy.
const PropertyApiOwner = struct {
    sealed: godot.annotations.Property(u32, .{ .usage = .none, .read_only = true }) = .init(1),
    seeded: godot.annotations.Property(u32, .{
        .usage = .none,
        .init = godot.annotations.Init(u32, five, .{}),
    }) = .init(0),
};

fn checkPropertyApiOwner() void {
    var owner: PropertyApiOwner = .{};
    var dummy_base: void = {};
    godot.annotations.initPropertyFields(PropertyApiOwner, void, &owner, &dummy_base);
    if (owner.seeded.value != 5) @compileError("annotations.initPropertyFields must assign .init results eagerly");
    if (owner.sealed.value != 1) @compileError("annotations.initPropertyFields must not touch fields without .init");
    if (!godot.annotations.property.isReadOnly(PropertyApiOwner, "sealed")) @compileError(".read_only properties must be read-only");
    if (godot.annotations.property.isWritable(PropertyApiOwner, "sealed")) @compileError(".read_only properties must not be writable");
    if (godot.annotations.property.getterFn(PropertyApiOwner, "sealed")(&owner) != 1) @compileError(".read_only properties must keep the default getter");
    if (!godot.annotations.property.hasCustomInitializer(@FieldType(PropertyApiOwner, "seeded"))) @compileError("annotations.property.hasCustomInitializer must detect .init");
}

comptime {
    checkMixedFieldOwner();
    checkPropertyApiOwner();
}

const godot = @import("godot");
