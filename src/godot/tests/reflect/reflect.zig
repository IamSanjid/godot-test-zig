//! Facade wiring for the `godot.reflect` compile-only checks.
//!
//! `reflect.zig` used to call the hierarchy/object/extension self-checks from a
//! container-level `comptime` block so a plain `zig build` still caught a broken
//! helper contract with no runtime caller. The checks (and their fake fixtures)
//! now live in the sibling test modules, which own them; this block keeps the
//! same facade-level dispatch for the test build.

comptime {
    _ = @import("base.zig");
    _ = @import("extension.zig");
    _ = @import("hierarchy.zig");
    _ = @import("meta.zig");
    _ = @import("objects.zig");
}
