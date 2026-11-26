//! Fixture `Resource` for the live typed-container test.
//!
//! `LiveTypedNode` uses this class as the element type of a typed object
//! `Array`; the exported scalar gives the class its own inspector state.

/// Resource instantiated from GDScript and stored in a typed object array.
pub const LiveResource = struct {
    pub const Extends = godot.classes.core.Resource;
    pub const GodotClassName = "LiveResource";

    base: godot.annotations.Base(Extends) = .{},

    /// Exported scalar so the fixture class has real state.
    points: godot.annotations.Property(i32, .{ .usage = .exported }) = .init(0),
};

const godot = @import("godot");
