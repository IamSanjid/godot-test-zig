//! Tests for the pure-Zig vector builtins.

test "vector constants match the engine" {
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = 0 }, single.Vector2.zero);
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = -1 }, single.Vector2.up);
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = 1 }, single.Vector2.down);
    try std.testing.expectEqual(single.Vector3{ .x = 0, .y = 0, .z = -1 }, single.Vector3.forward);
    try std.testing.expectEqual(single.Vector3{ .x = 0, .y = 0, .z = 1 }, single.Vector3.back);
    try std.testing.expectEqual(single.Vector2i{ .x = -2147483648, .y = -2147483648 }, single.Vector2i.minValue);
    try std.testing.expectEqual(single.Vector4{ .x = 1, .y = 1, .z = 1, .w = 1 }, single.Vector4.one);
}

test "float vector basics" {
    const a = single.Vector2{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f32, 5), a.length());
    try std.testing.expectEqual(@as(f32, 25), a.lengthSquared());
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), a.normalized().x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), a.normalized().y, 0.00001);
    try std.testing.expect(a.normalized().isNormalized());

    const b = single.Vector2{ .x = 1, .y = 2 };
    try std.testing.expectEqual(@as(f32, 11), a.dot(b));
    try std.testing.expectEqual(@as(f32, 2), a.cross(b));
    try std.testing.expectApproxEqAbs(@as(f32, 2.828427), a.distanceTo(b), 0.00001);

    try std.testing.expectEqual(single.Vector2{ .x = 4, .y = 6 }, a.add(b));
    try std.testing.expectEqual(single.Vector2{ .x = 2, .y = 2 }, a.sub(b));
    try std.testing.expectEqual(single.Vector2{ .x = 3, .y = 8 }, a.mul(b));
    try std.testing.expectEqual(single.Vector2{ .x = 3, .y = 2 }, a.div(b));
}

test "vector rotation and angles" {
    const rotated = (single.Vector2{ .x = 1, .y = 0 }).rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);

    const from_angle = single.Vector2.fromAngle(0);
    try std.testing.expectEqual(single.Vector2{ .x = 1, .y = 0 }, from_angle);

    const v3 = (single.Vector3{ .x = 1, .y = 0, .z = 0 }).rotated(single.Vector3.back, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v3.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v3.y, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v3.z, 0.00001);
}

test "integer vector methods" {
    const a = single.Vector2i{ .x = -3, .y = 7 };
    try std.testing.expectApproxEqAbs(@as(f32, -0.42857143), a.aspect(), 0.00001);
    try std.testing.expectEqual(single.Vector2i{ .x = 0, .y = 2 }, a.clamp(single.Vector2i.zero, single.Vector2i{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(single.Vector2i{ .x = 0, .y = 2 }, a.clampi(0, 2));
    try std.testing.expectEqual(single.Vector2i{ .x = -2, .y = 8 }, a.snapped(single.Vector2i{ .x = 2, .y = 4 }));
    try std.testing.expectEqual(@as(i64, 58), a.lengthSquared());
    try std.testing.expectEqual(single.Vector3i{ .x = 3, .y = 7, .z = 1 }, (single.Vector3i{ .x = -3, .y = 7, .z = -1 }).abs());
    try std.testing.expectEqual(@as(i64, 59), (single.Vector3i{ .x = -3, .y = 7, .z = -1 }).lengthSquared());
}

test "vector interpolation" {
    const a = single.Vector2.zero;
    const b = single.Vector2.one;
    try std.testing.expectEqual(single.Vector2{ .x = 0.5, .y = 0.5 }, a.lerp(b, 0.5));

    const cubic = a.cubicInterpolate(b, a, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubic.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubic.y, 0.00001);

    const bezier = a.bezierInterpolate(a, b, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bezier.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bezier.y, 0.00001);
}

test "octahedron round trip" {
    const values = [_]single.Vector3{
        single.Vector3{ .x = 0, .y = 0, .z = 1 },
        single.Vector3{ .x = 1, .y = 0, .z = 0 },
        single.Vector3{ .x = -1, .y = 0, .z = 0 },
        (single.Vector3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized(),
    };

    for (values) |value| {
        const encoded = value.octahedronEncode();
        const decoded = single.Vector3.octahedronDecode(encoded);
        try std.testing.expect(decoded.isEqualApprox(value));
    }
}

test "outer product" {
    const a = single.Vector3{ .x = 1, .y = 2, .z = 3 };
    const b = single.Vector3{ .x = 4, .y = 5, .z = 6 };
    const basis = a.outer(b);
    try std.testing.expectEqual(single.Vector3{ .x = 4, .y = 5, .z = 6 }, basis.rows[0]);
    try std.testing.expectEqual(single.Vector3{ .x = 8, .y = 10, .z = 12 }, basis.rows[1]);
    try std.testing.expectEqual(single.Vector3{ .x = 12, .y = 15, .z = 18 }, basis.rows[2]);
}

test "vector layout matches the GDExtension ABI" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(single.Vector2));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(single.Vector2i));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(single.Vector3));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(single.Vector3i));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Vector4));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Vector4i));

    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Vector2));
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(single.Basis));
}

fn checkVector2Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2 };
    const b: V = .{ .x = 3, .y = 4 };

    std.mem.doNotOptimizeAway(a.angle());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.angleToPoint(b));
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.limitLength(1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.project(b));
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.bezierInterpolate(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.bezierDerivative(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.moveToward(b, 0.5));
    std.mem.doNotOptimizeAway(a.rotated(0.5));
    std.mem.doNotOptimizeAway(a.orthogonal());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.aspect());
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.slide(b));
    std.mem.doNotOptimizeAway(a.bounce(b));
    std.mem.doNotOptimizeAway(a.reflect(b));
    std.mem.doNotOptimizeAway(a.cross(b));
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
    std.mem.doNotOptimizeAway(V.fromAngle(1));
}

test "double precision aliases and layout" {
    try std.testing.expect(single.real_t == f32);
    try std.testing.expect(double.real_t == f64);

    // Integer vectors are precision independent and shared between namespaces.
    try std.testing.expect(double.Vector2i == single.Vector2i);

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(double.Vector2));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(double.Vector3));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(double.Vector4));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(double.Basis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Vector2));
}

test "double precision math" {
    const V2 = double.Vector2;
    const V3 = double.Vector3;
    const V4 = double.Vector4;

    const a: V2 = .{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f64, 5), a.length());
    try std.testing.expectEqual(@as(f64, 25), a.lengthSquared());
    try std.testing.expect(a.normalized().isNormalized());

    const rotated = (V2{ .x = 1, .y = 0 }).rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotated.y, 1e-12);

    const cross = (V3{ .x = 1, .y = 0, .z = 0 }).cross(.{ .x = 0, .y = 1, .z = 0 });
    try std.testing.expectEqual(V3{ .x = 0, .y = 0, .z = 1 }, cross);

    const basis = (V3{ .x = 1, .y = 2, .z = 3 }).outer(.{ .x = 4, .y = 5, .z = 6 });
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(@TypeOf(basis)));
    try std.testing.expectEqual(V3{ .x = 4, .y = 5, .z = 6 }, basis.rows[0]);

    const lerped = (V4{ .x = 0, .y = 0, .z = 0, .w = 0 }).lerp(.{ .x = 1, .y = 1, .z = 1, .w = 1 }, 0.5);
    try std.testing.expectEqual(V4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, lerped);

    const decoded = V3.octahedronDecode((V3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized().octahedronEncode());
    try std.testing.expect(decoded.isEqualApprox((V3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized()));
}

test "all Vector2 float methods compile" {
    checkVector2Float(single.Vector2);
    checkVector2Float(double.Vector2);
}

fn checkVector2i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7 };
    const b: V = .{ .x = 2, .y = 4 };

    std.mem.doNotOptimizeAway(a.aspect());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
}

test "all Vector2i methods compile" {
    checkVector2i(single.Vector2i);
}

fn checkVector3Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2, .z = 3 };
    const b: V = .{ .x = 3, .y = 4, .z = 5 };
    const axis: V = .{ .x = 0, .y = 0, .z = 1 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.signedAngleTo(b, axis));
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.limitLength(1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.rotated(axis, 0.5));
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.bezierInterpolate(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.bezierDerivative(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.moveToward(b, 0.5));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.cross(b));
    std.mem.doNotOptimizeAway(a.outer(b).xform(a));
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.project(b));
    std.mem.doNotOptimizeAway(a.slide(b));
    std.mem.doNotOptimizeAway(a.bounce(b));
    std.mem.doNotOptimizeAway(a.reflect(b));
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.octahedronEncode());
    std.mem.doNotOptimizeAway(V.octahedronDecode(a.octahedronEncode()));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
}

test "all Vector3 float methods compile" {
    checkVector3Float(single.Vector3);
    checkVector3Float(double.Vector3);
}

fn checkVector3i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7, .z = 1 };
    const b: V = .{ .x = 2, .y = 4, .z = 6 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
}

test "all Vector3i methods compile" {
    checkVector3i(single.Vector3i);
}

fn checkVector4Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2, .z = 3, .w = 4 };
    const b: V = .{ .x = 3, .y = 4, .z = 5, .w = 6 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
}

test "all Vector4 float methods compile" {
    checkVector4Float(single.Vector4);
    checkVector4Float(double.Vector4);
}

fn checkVector4i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7, .z = 1, .w = 2 };
    const b: V = .{ .x = 2, .y = 4, .z = 6, .w = 8 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
}

test "all Vector4i methods compile" {
    checkVector4i(single.Vector4i);
}

const std = @import("std");

const godot = @import("godot");
const double = vector.double;
const single = vector.single;
const vector = godot.builtins.vector;
