//! Tests for the pure-Zig `Basis` builtin.

test "Basis column members" {
    const B = basis_mod.single.Basis;
    var basis = B.identity;
    basis.setX(.{ .x = 1, .y = 2, .z = 3 });
    basis.setY(.{ .x = 4, .y = 5, .z = 6 });
    basis.setZ(.{ .x = 7, .y = 8, .z = 9 });
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, basis.getX());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 4, .y = 5, .z = 6 }, basis.getY());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 7, .y = 8, .z = 9 }, basis.getZ());
}

test "Basis layout" {
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(basis_mod.single.Basis));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(basis_mod.double.Basis));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(basis_mod.single.Basis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(basis_mod.double.Basis));
}

test "Basis identity and transformations" {
    const B = basis_mod.single.Basis;
    const V = vector.single.Vector3;

    const identity = B.identity;
    try std.testing.expect(identity.isOrthonormal());
    try std.testing.expectEqual(V{ .x = 1, .y = 2, .z = 3 }, identity.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const scale = B.fromScale(.{ .x = 2, .y = 3, .z = 4 });
    try std.testing.expectEqual(@as(f32, 24), scale.determinant());
    try std.testing.expectEqual(V{ .x = 2, .y = 6, .z = 12 }, scale.xform(.{ .x = 1, .y = 2, .z = 3 }));
    try std.testing.expectEqual(V{ .x = 2, .y = 3, .z = 4 }, scale.getScale());

    const inverse = scale.inverse();
    try std.testing.expect(inverse.mul(scale).isEqualApprox(identity));

    const transposed = scale.transposed();
    try std.testing.expectEqual(V{ .x = 2, .y = 0, .z = 0 }, transposed.getColumn(0));

    const rotation = B.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);
    try std.testing.expect(rotation.isOrthonormal());
    try std.testing.expect(rotation.isConformal());
    try std.testing.expectEqual(@as(f32, 1), rotation.determinant());
}

test "Basis quaternion and slerp" {
    const B = basis_mod.single.Basis;

    const rotation = B.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 4.0);
    const quaternion_value = rotation.getRotationQuaternion();
    try std.testing.expect(quaternion_value.isNormalized());

    const round_trip = B.fromQuaternion(quaternion_value);
    try std.testing.expect(round_trip.isEqualApprox(rotation));

    const slerped = B.identity.slerp(rotation, 0.5);
    const transformed = slerped.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.9238795), transformed.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3826834), transformed.y, 0.0001);
}

test "Basis Euler orders round-trip" {
    const B = basis_mod.single.Basis;
    const euler = vector.single.Vector3{ .x = 0.1, .y = 0.2, .z = 0.3 };

    for ([_]EulerOrder{ .xyz, .xzy, .yxz, .yzx, .zxy, .zyx }) |order| {
        const rotation = B.fromEuler(euler, order);
        const round_trip = rotation.getEuler(order);
        try std.testing.expectApproxEqAbs(euler.x, round_trip.x, 0.00001);
        try std.testing.expectApproxEqAbs(euler.y, round_trip.y, 0.00001);
        try std.testing.expectApproxEqAbs(euler.z, round_trip.z, 0.00001);
    }
}

test "Basis orthonormalized and lookingAt" {
    const B = basis_mod.single.Basis;

    const skew = B.fromRows(
        .{ .x = 1, .y = 2, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 2 },
    );
    try std.testing.expect(!skew.isOrthonormal());
    try std.testing.expect(skew.orthonormalized().isOrthonormal());

    const look = B.lookingAt(.{ .x = 1, .y = 0, .z = 0 }, .{ .x = 0, .y = 1, .z = 0 }, false);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 0, .y = 1, .z = 0 }, look.getColumn(1));

    const double_look = basis_mod.double.Basis.lookingAt(
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        false,
    );
    try std.testing.expect(double_look.isOrthonormal());
}

const std = @import("std");

const godot = @import("godot");
const EulerOrder = godot.bindings.enums.EulerOrder;
const basis_mod = godot.builtins.basis;
const vector = godot.builtins.vector;
