//! Tests for the pure-Zig `Quaternion` builtin.

test "Quaternion layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(quaternion_mod.single.Quaternion));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(quaternion_mod.double.Quaternion));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(quaternion_mod.single.Quaternion));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(quaternion_mod.double.Quaternion));
}

test "Quaternion axis-angle and transform" {
    const Q = quaternion_mod.single.Quaternion;

    const rotation = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    try std.testing.expect(rotation.isNormalized());
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), rotation.getAngle(), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotation.getAxis().z, 0.00001);

    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);

    const inverse_rotation = rotation.inverse();
    try std.testing.expect(inverse_rotation.mul(rotation).isEqualApprox(Q.identity));
}

test "Quaternion interpolation and euler" {
    const Q = quaternion_mod.single.Quaternion;
    const V = vector.single.Vector3;

    const from = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, 0);
    const to = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi);
    const half = from.slerp(to, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), half.getAngle(), 0.00001);

    const euler = V{ .x = 0.1, .y = 0.2, .z = 0.3 };
    const quat = Q.fromEuler(euler);
    const round_trip = quat.getEuler();
    try std.testing.expectApproxEqAbs(euler.x, round_trip.x, 0.00001);
    try std.testing.expectApproxEqAbs(euler.y, round_trip.y, 0.00001);
    try std.testing.expectApproxEqAbs(euler.z, round_trip.z, 0.00001);

    const cubic = from.sphericalCubicInterpolate(to, from, to, 0.5);
    try std.testing.expect(cubic.isFinite());
    const cubic_time = from.sphericalCubicInterpolateInTime(to, from, to, 0.5, 1, 0, 2);
    try std.testing.expect(cubic_time.isFinite());
}

test "all Quaternion methods compile" {
    const Q = quaternion_mod.single.Quaternion;
    const a = Q.fromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, 0.5);
    const b = Q.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, 1.0);

    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.log());
    std.mem.doNotOptimizeAway(a.exp());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerpni(b, 0.5));
    std.mem.doNotOptimizeAway(a.sphericalCubicInterpolate(b, a, b, 0.5));
    std.mem.doNotOptimizeAway(a.sphericalCubicInterpolateInTime(b, a, b, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(Q.fromEuler(.{ .x = 0.1, .y = 0.2, .z = 0.3 }));
    std.mem.doNotOptimizeAway(a.getEuler());
    std.mem.doNotOptimizeAway(a.getAxis());
    std.mem.doNotOptimizeAway(a.getAngle());
    std.mem.doNotOptimizeAway(a.add(b));
    std.mem.doNotOptimizeAway(a.sub(b));
    std.mem.doNotOptimizeAway(a.negate());
    std.mem.doNotOptimizeAway(a.scale(2));
    std.mem.doNotOptimizeAway(a.dividedBy(2));
    std.mem.doNotOptimizeAway(a.mul(b));
    std.mem.doNotOptimizeAway(a.xform(.{ .x = 1, .y = 2, .z = 3 }));
    std.mem.doNotOptimizeAway(Q.fromBasisRows(a.toBasisRows()));
}

test "Quaternion double precision" {
    const Q = quaternion_mod.double.Quaternion;
    const rotation = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotated.y, 1e-12);
}

const std = @import("std");

const godot = @import("godot");
const quaternion_mod = godot.builtins.quaternion;
const vector = godot.builtins.vector;
