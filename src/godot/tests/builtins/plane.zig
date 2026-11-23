//! Tests for the pure-Zig `Plane` builtin.

test "Plane component members" {
    const P = plane_mod.single.Plane;
    var plane = P.init(.{ .x = 1, .y = 2, .z = 3 }, 4);
    try std.testing.expectEqual(@as(f32, 1), plane.getX());
    try std.testing.expectEqual(@as(f32, 2), plane.getY());
    try std.testing.expectEqual(@as(f32, 3), plane.getZ());
    plane.setX(7);
    plane.setY(8);
    plane.setZ(9);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 7, .y = 8, .z = 9 }, plane.normal);
}

test "Plane layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(plane_mod.single.Plane));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(plane_mod.double.Plane));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(plane_mod.single.Plane));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(plane_mod.double.Plane));
}

test "Plane basics" {
    const P = plane_mod.single.Plane;
    const V = vector.single.Vector3;

    const plane = P.init(.{ .x = 0, .y = 1, .z = 0 }, 2);
    try std.testing.expectEqual(V{ .x = 0, .y = 2, .z = 0 }, plane.getCenter());
    try std.testing.expectApproxEqAbs(@as(f32, 3), plane.distanceTo(.{ .x = 0, .y = 5, .z = 0 }), 0.00001);
    try std.testing.expect(plane.isPointOver(.{ .x = 0, .y = 3, .z = 0 }));
    try std.testing.expect(!plane.isPointOver(.{ .x = 0, .y = 1, .z = 0 }));
    try std.testing.expect(plane.hasPoint(.{ .x = 10, .y = 2, .z = 0 }, 0.00001));
    try std.testing.expectEqual(V{ .x = 0, .y = 2, .z = 0 }, plane.project(.{ .x = 0, .y = 5, .z = 0 }));

    const normalized = P.init(.{ .x = 0, .y = 2, .z = 0 }, 4).normalized();
    try std.testing.expectEqual(V{ .x = 0, .y = 1, .z = 0 }, normalized.normal);
    try std.testing.expectEqual(@as(f32, 2), normalized.d);
}

test "Plane intersections" {
    const P = plane_mod.single.Plane;
    const V = vector.single.Vector3;

    const plane_a = P.planeYZ;
    const plane_b = P.planeXZ;
    const plane_c = P.init(.{ .x = 0, .y = 0, .z = 1 }, 3);

    try std.testing.expectEqual(V{ .x = 0, .y = 0, .z = 3 }, plane_a.intersect3(plane_b, plane_c).?);

    const hit = plane_a.intersectsRay(.{ .x = -2, .y = 1, .z = 1 }, .{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expect(hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hit.?.x, 0.00001);
    try std.testing.expect(plane_a.intersectsRay(.{ .x = -2, .y = 1, .z = 1 }, .{ .x = -1, .y = 0, .z = 0 }) == null);

    const segment_hit = plane_a.intersectsSegment(.{ .x = -1, .y = 1, .z = 1 }, .{ .x = 1, .y = 1, .z = 1 });
    try std.testing.expect(segment_hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), segment_hit.?.x, 0.00001);
}

test "all Plane methods compile" {
    const P = plane_mod.single.Plane;
    const a = P.init(.{ .x = 0, .y = 1, .z = 0 }, 2);
    const b = P.init(.{ .x = 1, .y = 0, .z = 0 }, 1);
    const c = P.init(.{ .x = 0, .y = 0, .z = 1 }, 3);

    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.getCenter());
    std.mem.doNotOptimizeAway(a.isPointOver(.{ .x = 0, .y = 3, .z = 0 }));
    std.mem.doNotOptimizeAway(a.distanceTo(.{ .x = 0, .y = 3, .z = 0 }));
    std.mem.doNotOptimizeAway(a.hasPoint(.{ .x = 0, .y = 2, .z = 0 }, 0.00001));
    std.mem.doNotOptimizeAway(a.project(.{ .x = 0, .y = 3, .z = 0 }));
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isEqualApproxAnySide(a.negate()));
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.intersect3(b, c));
    std.mem.doNotOptimizeAway(a.intersectsRay(.{ .x = -1, .y = 2, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }));
    std.mem.doNotOptimizeAway(a.intersectsSegment(.{ .x = -1, .y = 2, .z = 0 }, .{ .x = 1, .y = 2, .z = 0 }));

    const xform = .{
        .basis = basis_mod.single.Basis.identity,
        .origin = vector.single.Vector3{ .x = 2, .y = 0, .z = 0 },
    };
    std.mem.doNotOptimizeAway(a.transformed(xform));
}

test "Plane double precision" {
    const P = plane_mod.double.Plane;
    const plane = P.init(.{ .x = 0, .y = 1, .z = 0 }, 2);
    try std.testing.expectApproxEqAbs(@as(f64, 3), plane.distanceTo(.{ .x = 0, .y = 5, .z = 0 }), 1e-12);
}

const std = @import("std");

const godot = @import("godot");
const basis_mod = godot.builtins.basis;
const plane_mod = godot.builtins.plane;
const vector = godot.builtins.vector;
