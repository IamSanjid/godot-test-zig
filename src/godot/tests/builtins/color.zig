//! Tests for the pure-Zig `Color` builtin.

test "Color layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Color));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(Color));
}

test "Color encoding" {
    const red = Color.init(1, 0, 0, 1);
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), red.toRgba32());
    try std.testing.expectEqual(@as(u32, 0xFFFF0000), red.toArgb32());
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), red.toAbgr32());
    try std.testing.expectEqual(@as(u64, 0xFFFF00000000FFFF), red.toRgba64());

    try std.testing.expectEqual(red, Color.hex(0xFF0000FF));
    try std.testing.expectEqual(red, Color.hex64(0xFFFF00000000FFFF));
}

test "Color HSV and conversions" {
    const cyan = Color.fromHsv(0.5, 1, 1, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), cyan.r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), cyan.g, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), cyan.b, 0.00001);

    const linear = Color.init(0.5, 0.5, 0.5, 1).srgbToLinear();
    const round_trip = linear.linearToSrgb();
    try std.testing.expect(round_trip.isEqualApprox(Color.init(0.5, 0.5, 0.5, 1)));

    try std.testing.expect(redEqualsColor());
}

fn redEqualsColor() bool {
    return Color.red.isEqualApprox(Color.init(1, 0, 0, 1));
}

test "Color operations" {
    const base = Color.init(0.25, 0.5, 0.75, 1);

    try std.testing.expectApproxEqAbs(@as(f32, 0.625), base.lerp(Color.white, 0.5).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), base.lightened(1).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), base.darkened(1).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), base.inverted().r, 0.00001);
    try std.testing.expect(base.getLuminance() > 0);

    const clamped = Color.init(-1, 2, 0.5, 1).clamp(Color.black, Color.white);
    try std.testing.expectEqual(Color.init(0, 1, 0.5, 1), clamped);

    const blended = Color.init(1, 0, 0, 0.5).blend(Color.init(0, 0, 1, 0.5));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), blended.r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0 / 3.0), blended.b, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), blended.a, 0.00001);
}

test "Color computed members" {
    var value = Color.init(0.2, 0.4, 0.8, 1);

    value.setR8(128);
    value.setG8(64);
    value.setB8(32);
    value.setA8(255);
    try std.testing.expectEqual(@as(i32, 128), value.getR8());
    try std.testing.expectEqual(@as(i32, 64), value.getG8());
    try std.testing.expectEqual(@as(i32, 32), value.getB8());
    try std.testing.expectEqual(@as(i32, 255), value.getA8());

    const hsv = Color.init(0.2, 0.4, 0.8, 1);
    const hue = hsv.getH();
    const saturation = hsv.getS();
    const brightness = hsv.getV();
    value.setH(hue);
    value.setS(saturation);
    value.setV(brightness);
    try std.testing.expect(value.getH() >= 0 and value.getH() <= 1);

    const okhsl = Color.fromOkHsl(0.5, 0.5, 0.5, 1);
    try std.testing.expect(okhsl.getOkHslH() >= 0);
    value.setOkHslH(0.25);
    value.setOkHslS(0.5);
    value.setOkHslL(0.5);
    try std.testing.expect(value.getOkHslH() >= 0);
}

test "all Color methods compile" {
    const value = Color.init(0.25, 0.5, 0.75, 1);
    const other = Color.init(0.1, 0.2, 0.3, 0.4);

    std.mem.doNotOptimizeAway(value.toRgba32());
    std.mem.doNotOptimizeAway(value.toArgb32());
    std.mem.doNotOptimizeAway(value.toAbgr32());
    std.mem.doNotOptimizeAway(value.toRgba64());
    std.mem.doNotOptimizeAway(value.toArgb64());
    std.mem.doNotOptimizeAway(value.toAbgr64());
    std.mem.doNotOptimizeAway(value.clamp(Color.black, Color.white));
    std.mem.doNotOptimizeAway(value.inverted());
    std.mem.doNotOptimizeAway(value.lerp(other, 0.5));
    std.mem.doNotOptimizeAway(value.lightened(0.5));
    std.mem.doNotOptimizeAway(value.darkened(0.5));
    std.mem.doNotOptimizeAway(value.blend(other));
    std.mem.doNotOptimizeAway(value.getLuminance());
    std.mem.doNotOptimizeAway(value.srgbToLinear());
    std.mem.doNotOptimizeAway(value.linearToSrgb());
    std.mem.doNotOptimizeAway(value.isEqualApprox(other));
    std.mem.doNotOptimizeAway(Color.hex(0x11223344));
    std.mem.doNotOptimizeAway(Color.hex64(0x1122334455667788));
    std.mem.doNotOptimizeAway(Color.fromHsv(0.5, 0.5, 0.5, 1));
    std.mem.doNotOptimizeAway(Color.fromOkHsl(0.5, 0.5, 0.5, 1));
    std.mem.doNotOptimizeAway(value.getOkHslH());
    std.mem.doNotOptimizeAway(value.getOkHslS());
    std.mem.doNotOptimizeAway(value.getOkHslL());
    std.mem.doNotOptimizeAway(Color.fromRgbe9995(0x12345678));
    std.mem.doNotOptimizeAway(Color.fromRgba8(1, 2, 3, 4));
}

test "Color constants" {
    try std.testing.expect(Color.alice_blue.isEqualApprox(Color.init(0.9411765, 0.972549, 1, 1)));
    try std.testing.expect(Color.transparent.isEqualApprox(Color.init(1, 1, 1, 0)));
    try std.testing.expect(Color.web_gray.isEqualApprox(Color.init(0.5019608, 0.5019608, 0.5019608, 1)));
}

const std = @import("std");

const godot = @import("godot");
const Color = godot.builtins.Color;
