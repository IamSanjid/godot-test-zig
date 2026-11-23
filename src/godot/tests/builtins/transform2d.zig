//! Tests for the pure-Zig `Transform2D` builtin.

test "Transform2D member aliases" {
    const T = transform2d_mod.single.Transform2D;
    var xform = T.identity;
    xform.setX(.{ .x = 1, .y = 2 });
    xform.setY(.{ .x = 3, .y = 4 });
    xform.setOrigin(.{ .x = 5, .y = 6 });
    try std.testing.expectEqual(vector.single.Vector2{ .x = 1, .y = 2 }, xform.getX());
    try std.testing.expectEqual(vector.single.Vector2{ .x = 3, .y = 4 }, xform.getY());
    try std.testing.expectEqual(vector.single.Vector2{ .x = 5, .y = 6 }, xform.getOrigin());
}

test "Transform2D layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(transform2d_mod.single.Transform2D));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(transform2d_mod.double.Transform2D));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(transform2d_mod.single.Transform2D));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(transform2d_mod.double.Transform2D));
}

test "Transform2D basics" {
    const T = transform2d_mod.single.Transform2D;
    const V = vector.single.Vector2;

    const rotation = T.identity.rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), rotation.getRotation(), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotation.determinant(), 0.00001);
    try std.testing.expect(rotation.isConformal());
    try std.testing.expect(rotation.orthonormalized().isEqualApprox(rotation));

    const scaled = T.identity.scaled(.{ .x = 2, .y = 3 });
    try std.testing.expectEqual(V{ .x = 2, .y = 3 }, scaled.getScale());

    const translated = T.identity.translated(.{ .x = 4, .y = 5 });
    try std.testing.expectEqual(V{ .x = 4, .y = 5 }, translated.getOrigin());

    const xform = T.identity.translated(.{ .x = 4, .y = 5 }).rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), xform.getScale().x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), xform.getScale().y, 0.00001);
}

test "Transform2D inverse and basis transforms" {
    const T = transform2d_mod.single.Transform2D;
    const V = vector.single.Vector2;

    const xform = T.identity.scaled(.{ .x = 2, .y = 3 }).translated(.{ .x = 4, .y = 5 });
    const inverse = xform.affineInverse();
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), inverse.getScale().x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), inverse.getScale().y, 0.00001);

    const point = V{ .x = 3, .y = 4 };
    const transformed = xform.basisXform(point).add(xform.getOrigin());
    const restored = inverse.basisXform(transformed).add(inverse.getOrigin());
    try std.testing.expectApproxEqAbs(point.x, restored.x, 0.00001);
    try std.testing.expectApproxEqAbs(point.y, restored.y, 0.00001);

    const rotation = T.identity.rotated(0.7);
    try std.testing.expect(rotation.basisXformInv(rotation.basisXform(point)).isEqualApprox(point));
}

test "Transform2D interpolation and lookingAt" {
    const T = transform2d_mod.single.Transform2D;

    const start = T.identity.translated(.{ .x = 0, .y = 0 });
    const end = T.identity.rotated(std.math.pi / 2.0).translated(.{ .x = 4, .y = 0 });
    const midway = start.interpolateWith(end, 0.5);
    try std.testing.expectEqual(vector.single.Vector2{ .x = 2, .y = 0 }, midway.getOrigin());
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 4.0), midway.getRotation(), 0.00001);

    const look = T.identity.translated(.{ .x = 1, .y = 2 }).lookingAt(.{ .x = 1, .y = 3 });
    try std.testing.expect(look.isFinite());
    try std.testing.expectEqual(vector.single.Vector2{ .x = 1, .y = 2 }, look.getOrigin());
}

test "Transform2D double precision" {
    const T = transform2d_mod.double.Transform2D;
    const rotation = T.identity.rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotation.determinant(), 1e-12);
    const scale = T.identity.scaled(.{ .x = 2, .y = 3 }).getScale();
    try std.testing.expectEqual(vector.double.Vector2{ .x = 2, .y = 3 }, scale);
}

const std = @import("std");

const godot = @import("godot");
const transform2d_mod = godot.builtins.transform2d;
const vector = godot.builtins.vector;
