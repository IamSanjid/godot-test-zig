//! Tests for the precision-selected builtin math constants.

test "precision-selected constants" {
    try std.testing.expectEqual(@as(f64, 0.001), constants.single.unit_epsilon);
    try std.testing.expectEqual(@as(f64, 0.00001), constants.double.unit_epsilon);
    try std.testing.expectEqual(constants.single, constants.For(f32));
    try std.testing.expectEqual(constants.double, constants.For(f64));
}

const std = @import("std");

const godot = @import("godot");
const constants = godot.builtins.constants;
