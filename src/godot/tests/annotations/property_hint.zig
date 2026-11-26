//! Type-derived property hints, exercised through the public descriptor API.
//!
//! `annotations.property_hint.resolve` is internal; the same behavior is
//! observable through `godot.annotations.property.descriptors`, which applies it to
//! visible fields without an explicit `.hint`/`.hint_string`. Converter values
//! such as `ownership.Ref` resolve through their engine object representation.

fn check(comptime condition: bool, comptime message: []const u8) void {
    if (!condition) @compileError("property_hint tests: " ++ message);
}

fn same(comptime a: []const u8, comptime b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const HintOwner = struct {
    scalar: godot.annotations.Property(u32, .{ .usage = .exported }) = .init(0),
    plain_object: godot.annotations.Property(?*godot.classes.core.Object, .{ .usage = .exported }) = .init(null),
    node: godot.annotations.Property(?*godot.classes.core.Node, .{ .usage = .exported }) = .init(null),
    resource: godot.annotations.Property(godot.ownership.Ref(godot.classes.core.Resource), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(.init(null)),
    texture: godot.annotations.Property(godot.ownership.Ref(godot.classes.core.Texture2D), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(.init(null)),
    ref_counted: godot.annotations.Property(godot.ownership.Ref(godot.classes.core.RefCounted), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(.init(null)),
};

comptime {
    const descs = godot.annotations.property.descriptors(HintOwner);

    // Scalars have no type-inherent hint and no class name.
    check(descs[0].hint == .none, "scalars have no hint");
    check(same(descs[0].hint_string, ""), "scalars have no hint string");
    check(descs[0].class_name == null, "scalars have no class name");

    check(descs[1].hint == .none, "plain object pointers have no picker hint");
    check(same(descs[1].hint_string, ""), "plain object pointers have no hint string");
    check(descs[1].class_name != null and same(descs[1].class_name.?, "Object"), "plain object class name");

    check(descs[2].hint == .node_type, "Node pointers use the node picker");
    check(same(descs[2].hint_string, "Node"), "Node hint string");
    check(descs[2].class_name != null and same(descs[2].class_name.?, "Node"), "Node class name");

    // Owning wrappers derive hints from their conversion engine representation.
    check(descs[3].value_type == godot.ownership.Ref(godot.classes.core.Resource), "Ref(Resource) stays the declared value type");
    check(descs[3].hint == .resource_type, "Ref(Resource) uses the resolved resource picker");
    check(same(descs[3].hint_string, "Resource"), "Ref(Resource) hint string");
    check(descs[3].class_name != null and same(descs[3].class_name.?, "Resource"), "Ref(Resource) class name");
    check(godot.internal.conversion.variantType(descs[3].value_type) == .object, "Ref(Resource) keeps the object Variant type");

    check(descs[4].hint == .resource_type, "Ref(Texture2D) uses the resource picker");
    check(same(descs[4].hint_string, "Texture2D"), "Ref(Texture2D) hint string uses the engine class name");
    check(descs[4].class_name != null and same(descs[4].class_name.?, "Texture2D"), "Ref(Texture2D) class name");

    check(descs[5].hint == .none, "Ref(RefCounted) has no picker hint");
    check(descs[5].class_name != null and same(descs[5].class_name.?, "RefCounted"), "Ref(RefCounted) class name");
}

const std = @import("std");

const godot = @import("godot");
