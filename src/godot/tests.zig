//! Hand-written runtime tests plus full semantic analysis of generated output.
//!
//! `zig build test-godot` regenerates bindings/codegen for the selected build
//! configuration, then compiles and runs this test root. The generated layers
//! are lazy in Zig, so `refAllDecls` is used to force their declarations through
//! the semantic analyzer even though most of them are not called by runtime
//! tests.

const std = @import("std");
const bindings = @import("bindings");
const godot = @import("godot.zig");

fn refAllDeclsShallow(comptime M: type) void {
    @setEvalBranchQuota(1_000_000);
    std.testing.refAllDecls(M);
    inline for (comptime std.meta.declarations(M)) |decl_name| {
        const value = @field(M, decl_name);
        if (comptime @TypeOf(value) == type) {
            const info = @typeInfo(value);
            switch (info) {
                .@"struct", .@"enum", .@"union", .@"opaque" => {
                    if (comptime @hasDecl(value, "GodotClassName")) std.testing.refAllDecls(value);
                },
                else => {},
            }
        }
    }
}

test "generated bindings and codegen declarations are analyzed" {
    refAllDeclsShallow(bindings);
    refAllDeclsShallow(bindings.interface);
    refAllDeclsShallow(bindings.classes);
    refAllDeclsShallow(bindings.classes.core);
    refAllDeclsShallow(bindings.classes.editor);
    refAllDeclsShallow(bindings.builtins);
    refAllDeclsShallow(bindings.constants);
    refAllDeclsShallow(bindings.enums);
    refAllDeclsShallow(bindings.native);
    refAllDeclsShallow(bindings.singletons);
    refAllDeclsShallow(bindings.utility);
    refAllDeclsShallow(bindings.utility.general);
    refAllDeclsShallow(bindings.utility.math);
    refAllDeclsShallow(bindings.utility.random);

    refAllDeclsShallow(godot.classes);
    refAllDeclsShallow(godot.classes.core);
    refAllDeclsShallow(godot.classes.editor);
    // Hand-written builtin structs contain intentional compile-error decls for
    // unsupported variants (integer vector-only members), so analyze the
    // generated codegen builtins explicitly instead of refAllDecls on the mixed
    // aggregator.
    refAllDeclsShallow(godot.builtins.String);
    refAllDeclsShallow(godot.builtins.StringName);
    refAllDeclsShallow(godot.builtins.NodePath);
    refAllDeclsShallow(godot.builtins.Callable);
    refAllDeclsShallow(godot.builtins.Signal);
    refAllDeclsShallow(godot.builtins.Array);
    refAllDeclsShallow(godot.builtins.Dictionary);
    refAllDeclsShallow(godot.builtins.PackedByteArray);
    refAllDeclsShallow(godot.builtins.PackedColorArray);
    refAllDeclsShallow(godot.builtins.PackedFloat32Array);
    refAllDeclsShallow(godot.builtins.PackedFloat64Array);
    refAllDeclsShallow(godot.builtins.PackedInt32Array);
    refAllDeclsShallow(godot.builtins.PackedInt64Array);
    refAllDeclsShallow(godot.builtins.PackedStringArray);
    refAllDeclsShallow(godot.builtins.PackedVector2Array);
    refAllDeclsShallow(godot.builtins.PackedVector3Array);
    refAllDeclsShallow(godot.builtins.PackedVector4Array);
    refAllDeclsShallow(godot.constants);
    refAllDeclsShallow(godot.enums);
    refAllDeclsShallow(godot.native);
    refAllDeclsShallow(godot.singletons);
    refAllDeclsShallow(godot.utility);
    refAllDeclsShallow(godot.utility.general);
    refAllDeclsShallow(godot.utility.math);
    refAllDeclsShallow(godot.utility.random);
}

test "generated Variant uses the engine ABI alignment" {
    try std.testing.expectEqual(@as(usize, 8), @alignOf(bindings.builtins.Variant));
}

test "hand-written runtime tests are linked" {
    _ = @import("abi.zig");
    _ = @import("annotations/annotations.zig");
    _ = @import("builtins/builtins.zig");
    _ = @import("reflect/reflect.zig");
    _ = @import("registration/property.zig");
}
