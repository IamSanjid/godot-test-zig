//! Test aggregator for the generator. `zig build test-bindgen` uses this file
//! as the test root so tests in the shared model and both backends compile.

test {
    _ = @import("model/api_options.zig");
    _ = @import("model/cli.zig");
    _ = @import("model/ExtensionApiJson.zig");
    _ = @import("model/InterfaceJson.zig");
    _ = @import("model/docs.zig");
    _ = @import("model/defaults.zig");
    _ = @import("model/names.zig");
    _ = @import("model/types.zig");
    _ = @import("model/result_init.zig");
    _ = @import("model/enum_utils.zig");
    _ = @import("model/enum_emit.zig");
    _ = @import("model/builtin_names.zig");
    _ = @import("model/resolver.zig");

    _ = @import("bindgen/Options.zig");
    _ = @import("bindgen/Registry.zig");
    _ = @import("bindgen/common.zig");
    _ = @import("bindgen/custom.zig");
    _ = @import("bindgen/class_templates.zig");
    _ = @import("bindgen/enum.zig");
    _ = @import("bindgen/handle.zig");
    _ = @import("bindgen/alias.zig");
    _ = @import("bindgen/structure.zig");
    _ = @import("bindgen/function.zig");
    _ = @import("bindgen/interface.zig");
    _ = @import("bindgen/builtin.zig");
    _ = @import("bindgen/global.zig");
    _ = @import("bindgen/class.zig");
    _ = @import("bindgen/singleton.zig");
    _ = @import("bindgen/native.zig");
    _ = @import("bindgen/utility.zig");
    _ = @import("bindgen/builtin_catalog.zig");

    _ = @import("codegen/Options.zig");
    _ = @import("codegen/type_mapping.zig");
    _ = @import("codegen/custom.zig");
    _ = @import("codegen/templates.zig");
    _ = @import("codegen/overrides.zig");
    _ = @import("codegen/class.zig");
    _ = @import("codegen/builtin.zig");
    _ = @import("codegen/artifacts.zig");
    _ = @import("codegen/utility.zig");
}

test "shared naming policy" {
    const std = @import("std");
    try std.testing.expectEqualStrings(
        "get_node",
        comptime naming.comptimeConvert(.godot, .method, "getNode"),
    );
    try std.testing.expectEqualStrings(
        "getNode",
        comptime naming.comptimeConvert(.zig, .method, "get_node"),
    );
    try std.testing.expectEqualStrings(
        "CONNECT_DEFERRED",
        comptime naming.comptimeConvert(.godot, .enum_variant, "connect_deferred"),
    );
    try std.testing.expectEqualStrings(
        "connect_deferred",
        comptime naming.comptimeConvert(.zig, .enum_variant, "connect_deferred"),
    );
}

const naming = @import("naming");
