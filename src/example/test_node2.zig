//! Example namespace file discovered by the class-file scanner.

pub const TestNode2 = struct {
    pub const Extends = godot.classes.core.Node;

    v: u8 = 0,

    pub fn _ready(_: *const @This()) void {
        std.log.debug("Second read!", .{});
    }
};

const std = @import("std");

const godot = @import("godot");
