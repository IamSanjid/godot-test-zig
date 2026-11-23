//! Tests for the pure-Zig `Transform3D` builtin.

test "Transform3D layout" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(transform3d_mod.single.Transform3D));
    try std.testing.expectEqual(@as(usize, 96), @sizeOf(transform3d_mod.double.Transform3D));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(transform3d_mod.single.Transform3D));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(transform3d_mod.double.Transform3D));
}

test "Transform3D transform basics" {
    const T = transform3d_mod.single.Transform3D;
    const V = vector.single.Vector3;

    try std.testing.expectEqual(V{ .x = 1, .y = 2, .z = 3 }, T.identity.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const translated = T.identity.translated(.{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(V{ .x = 2, .y = 4, .z = 6 }, translated.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const scaled = T.identity.scaled(.{ .x = 2, .y = 3, .z = 4 });
    try std.testing.expectEqual(V{ .x = 2, .y = 6, .z = 12 }, scaled.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const combined = translated.mul(scaled);
    try std.testing.expectEqual(V{ .x = 3, .y = 8, .z = 15 }, combined.xform(.{ .x = 1, .y = 2, .z = 3 }));

    try std.testing.expect(combined.mul(combined.affineInverse()).isEqualApprox(T.identity));

    const rotation = T.init(basis_mod.single.Basis.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, 0.5), .{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expect(rotation.mul(rotation.inverse()).isEqualApprox(T.identity));
}

test "Transform3D rotation and AABB transform" {
    const T = transform3d_mod.single.Transform3D;
    const B = basis_mod.single.Basis;
    const AABB = aabb_mod.single.AABB;

    const rotation = T.init(B.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0), .zero);
    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);

    const box = AABB{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 1, .y = 2, .z = 3 } };
    const translated = T.identity.translated(.{ .x = 1, .y = 2, .z = 3 });
    const moved = translated.xformAabb(box);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, moved.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, moved.size);

    const scaled = T.identity.scaled(.{ .x = 2, .y = 3, .z = 4 });
    const resized = scaled.xformAabb(box);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 0, .y = 0, .z = 0 }, resized.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 2, .y = 6, .z = 12 }, resized.size);

    try std.testing.expect(box.transformed(translated).isEqualApprox(moved));
    try std.testing.expect(box.transformed(scaled).isEqualApprox(resized));
    try std.testing.expect(rotation.xformAabb(box).isEqualApprox(box.transformed(rotation)));
}

test "Transform3D interpolation and plane transforms" {
    const T = transform3d_mod.single.Transform3D;
    const P = plane_mod.single.Plane;
    const Box = aabb_mod.single.AABB;

    const started = T.identity;
    const ended = T.identity.translated(.{ .x = 4, .y = 0, .z = 0 });
    const midway = started.interpolateWith(ended, 0.5);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 2, .y = 0, .z = 0 }, midway.origin);

    const translated = T.identity.translated(.{ .x = 2, .y = 0, .z = 0 });
    const moved_plane = translated.xformPlane(P.init(.{ .x = 1, .y = 0, .z = 0 }, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 2), moved_plane.d, 0.00001);

    const box = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 2 } };
    try std.testing.expect(box.intersectsPlane(P.init(.{ .x = 1, .y = 0, .z = 0 }, 1)));
    try std.testing.expect(!box.intersectsPlane(P.init(.{ .x = 1, .y = 0, .z = 0 }, 3)));
}

test "Transform3D double precision" {
    const T = transform3d_mod.double.Transform3D;
    const translated = T.identity.translated(.{ .x = 1, .y = 2, .z = 3 });
    const transformed = translated.xform(.{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(vector.double.Vector3{ .x = 2, .y = 4, .z = 6 }, transformed);
}

const std = @import("std");

const godot = @import("godot");
const aabb_mod = godot.builtins.aabb;
const basis_mod = godot.builtins.basis;
const plane_mod = godot.builtins.plane;
const transform3d_mod = godot.builtins.transform3d;
const vector = godot.builtins.vector;
