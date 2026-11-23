//! Tests for the pure-Zig OKHSL conversion helpers.

test "okhsl grayscale and round-trip" {
    const gray = ok_color.okhslToSrgb(.{ .h = 0.5, .s = 0, .l = 0.5 });
    try std.testing.expectApproxEqAbs(gray.r, gray.g, 0.00001);
    try std.testing.expectApproxEqAbs(gray.g, gray.b, 0.00001);

    const source = ok_color.Rgb{ .r = 0.2, .g = 0.5, .b = 0.8 };
    const hsl = ok_color.srgbToOkhsl(source);
    const round_trip = ok_color.okhslToSrgb(hsl);
    try std.testing.expectApproxEqAbs(source.r, round_trip.r, 0.0001);
    try std.testing.expectApproxEqAbs(source.g, round_trip.g, 0.0001);
    try std.testing.expectApproxEqAbs(source.b, round_trip.b, 0.0001);
}

const std = @import("std");

const godot = @import("godot");
const ok_color = godot.builtins.ok_color;
