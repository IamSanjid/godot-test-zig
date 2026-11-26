//! Example namespace file discovered by the class-file scanner.

pub const TestNode2 = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},

    name: godot.annotations.Property(godot.builtins.String, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }).Init(.fromLatin1, .{"TheName2!"}),
    value: godot.annotations.Property(u32, .{
        .usage = .exported,
    }) = .init(0),

    pub fn _ready(self: *const @This()) void {
        std.log.debug("TestNode2! value: {}", .{self.value.get()});
        godot.utility.general.printRich(godot.builtins.Variant.borrow(godot.builtins.String, self.name.getPtrConst()).get(), .{});
    }
};

pub const TestResource = struct {
    pub const Extends = godot.classes.core.Resource;

    base: godot.annotations.Base(Extends) = .{},

    name: godot.annotations.Property(godot.builtins.String, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }).Init(.fromLatin1, .{"TheName2!"}),
    value: godot.annotations.Property(u32, .{
        .usage = .exported,
    }) = .init(0),
};

const std = @import("std");

const godot = @import("godot");
