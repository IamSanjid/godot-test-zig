//! Test aggregator for the bindgen. `zig build test-bindgen` uses this file as
//! the test root so tests in the emitter modules are compiled and run.

test {
    _ = @import("Options.zig");
    _ = @import("ExtensionApiJson.zig");
    _ = @import("gen/Registry.zig");
    _ = @import("gen/common.zig");
    _ = @import("gen/enum.zig");
    _ = @import("gen/handle.zig");
    _ = @import("gen/alias.zig");
    _ = @import("gen/structure.zig");
    _ = @import("gen/function.zig");
    _ = @import("gen/interface.zig");
    _ = @import("gen/builtin.zig");
    _ = @import("gen/enum_utils.zig");
    _ = @import("gen/enum_emit.zig");
    _ = @import("gen/docs.zig");
    _ = @import("gen/names.zig");
    _ = @import("gen/types.zig");
    _ = @import("gen/global.zig");
    _ = @import("gen/defaults.zig");
    _ = @import("gen/custom.zig");
    _ = @import("gen/ClassResolver.zig");
    _ = @import("gen/class.zig");
    _ = @import("gen/singleton.zig");
    _ = @import("gen/native.zig");
    _ = @import("gen/utility.zig");
    _ = @import("gen/class_templates.zig");
}
