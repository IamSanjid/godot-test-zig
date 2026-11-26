//! Raw-bindgen Variant fixed-argument support checks.
//!
//! Generated vararg wrappers wrap fixed arguments with the raw
//! `Variant.borrow(dispatcher, T, &arg)` helper. Zig analyzes generated function
//! bodies lazily, so an unsupported future API type would otherwise fail only
//! when a user first calls the method. Validate the resolved type while
//! generating so an API bump fails at bindgen time instead.

const std = @import("std");
const class_resolver = @import("resolver.zig");

/// True when the raw bindgen Variant.borrow helper supports this fixed argument
/// type. Variant arguments are passed through directly; class pointers,
/// primitives, enums and bitfields have dedicated raw paths.
pub fn supportsFixedArgument(resolved: class_resolver.ResolvedType) bool {
    return switch (resolved.kind) {
        .variant, .class_ptr, .primitive, .@"enum" => true,
        .builtin => isSupportedInlineBuiltin(resolved.zig),
        .native_ptr, .void => false,
    };
}

/// Inline builtins handled by the raw Variant.borrow pointer switch. Heap-backed
/// builtins and packed arrays are deliberately absent; they require the owning
/// Variant constructor path.
fn isSupportedInlineBuiltin(name: []const u8) bool {
    const n = if (std.mem.startsWith(u8, name, "builtins.")) name["builtins.".len..] else name;
    const supported = [_][]const u8{
        "String",
        "StringName",
        "NodePath",
        "RID",
        "Callable",
        "Signal",
        "Array",
        "Dictionary",
        "Vector2",
        "Vector2i",
        "Vector3",
        "Vector3i",
        "Vector4",
        "Vector4i",
        "Rect2",
        "Rect2i",
        "Plane",
        "Quaternion",
        "Color",
    };
    for (supported) |name_supported| {
        if (std.mem.eql(u8, n, name_supported)) return true;
    }
    return false;
}

test "raw fixed-argument support classification" {
    try std.testing.expect(supportsFixedArgument(.{ .kind = .primitive, .zig = "i64" }));
    try std.testing.expect(supportsFixedArgument(.{ .kind = .class_ptr, .zig = "*Node" }));
    try std.testing.expect(supportsFixedArgument(.{ .kind = .variant, .zig = "Variant" }));
    try std.testing.expect(supportsFixedArgument(.{ .kind = .builtin, .zig = "builtins.String" }));
    try std.testing.expect(supportsFixedArgument(.{ .kind = .builtin, .zig = "Color" }));
    try std.testing.expect(!supportsFixedArgument(.{ .kind = .builtin, .zig = "Transform2D" }));
    try std.testing.expect(!supportsFixedArgument(.{ .kind = .builtin, .zig = "PackedByteArray" }));
    try std.testing.expect(!supportsFixedArgument(.{ .kind = .native_ptr, .zig = "*Native" }));
}
