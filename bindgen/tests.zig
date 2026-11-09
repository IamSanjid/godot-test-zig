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
}
