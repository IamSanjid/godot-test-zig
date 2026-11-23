//! Tests for the pure-Zig `Projection` builtin.

test "Projection member aliases" {
    const P = projection_mod.single.Projection;
    var projection = P.identity;
    const x_value = vector.single.Vector4{ .x = 1, .y = 2, .z = 3, .w = 4 };
    const y_value = vector.single.Vector4{ .x = 5, .y = 6, .z = 7, .w = 8 };
    const z_value = vector.single.Vector4{ .x = 9, .y = 10, .z = 11, .w = 12 };
    const w_value = vector.single.Vector4{ .x = 13, .y = 14, .z = 15, .w = 16 };
    projection.setX(x_value);
    projection.setY(y_value);
    projection.setZ(z_value);
    projection.setW(w_value);
    try std.testing.expectEqual(x_value, projection.getX());
    try std.testing.expectEqual(y_value, projection.getY());
    try std.testing.expectEqual(z_value, projection.getZ());
    try std.testing.expectEqual(w_value, projection.getW());
}

test "Projection layout" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(projection_mod.single.Projection));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(projection_mod.double.Projection));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(projection_mod.single.Projection));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(projection_mod.double.Projection));
}

test "Projection perspective and inverse" {
    const P = projection_mod.single.Projection;
    const V4 = vector.single.Vector4;

    const perspective = P.createPerspective(60, 16.0 / 9.0, 0.1, 100, false);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), perspective.getZNear(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), perspective.getZFar(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0 / 9.0), perspective.getAspect(), 0.0001);
    try std.testing.expect(!perspective.isOrthogonal());
    try std.testing.expect(perspective.mul(perspective.inverse()).isEqualApprox(P.identity));

    const point: V4 = .{ .x = 0, .y = 0, .z = -1, .w = 1 };
    const projected = perspective.xform(point);
    try std.testing.expect(projected.w > 0);
    try std.testing.expectEqual(@as(i32, 0), perspective.getPixelsPerMeter(0));
}

test "Projection orthogonal and fit" {
    const P = projection_mod.single.Projection;
    const Box = aabb_mod.single.AABB;

    const orthogonal = P.createOrthogonal(-10, 10, -5, 5, 0.1, 100);
    try std.testing.expect(orthogonal.isOrthogonal());
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), orthogonal.getZNear(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), orthogonal.getZFar(), 0.0001);

    const bounds = Box{ .position = .{ .x = -2, .y = -4, .z = 1 }, .size = .{ .x = 4, .y = 8, .z = 2 } };
    const fit = P.createFitAabb(bounds);
    const min = fit.xformVector3(.{ .x = -2, .y = -4, .z = 1 });
    const max = fit.xformVector3(.{ .x = 2, .y = 4, .z = 3 });
    try std.testing.expectApproxEqAbs(@as(f32, -1), min.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), max.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), min.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), max.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), min.z, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), max.z, 0.0001);
}

test "Projection depth correction and planes" {
    const P = projection_mod.single.Projection;

    const correction = P.createDepthCorrection(true);
    try std.testing.expectEqual(@as(f32, -1), correction.columns[1].y);
    try std.testing.expectEqual(@as(f32, -0.5), correction.columns[2].z);

    const perspective = P.createPerspective(90, 1, 1, 10, false);
    const near = perspective.getProjectionPlane(.near);
    try std.testing.expect(near.isFinite());
    const far = perspective.getProjectionPlane(.far);
    try std.testing.expect(far.isFinite());
}

test "all Projection methods compile" {
    const P = projection_mod.single.Projection;
    const Box = aabb_mod.single.AABB;
    const Plane = plane_mod.single.Plane;

    const perspective = P.createPerspective(60, 1.5, 0.1, 100, false);
    const hmd = P.createPerspectiveHmd(60, 1.5, 0.1, 100, false, 1, 0.06, 2);
    const for_hmd = P.createForHmd(1, 1.5, 0.06, 0.1, 0.05, 1.2, 0.1, 100);
    const atlas = P.createLightAtlasRect(rect_mod.single.Rect2.init(.{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 }));
    const orthogonal = P.createOrthogonal(-1, 1, -1, 1, 0.1, 100);
    const orthogonal_aspect = P.createOrthogonalAspect(2, 1.5, 0.1, 100, false);
    const frustum = P.createFrustum(-1, 1, -1, 1, 0.1, 100);
    const frustum_aspect = P.createFrustumAspect(2, 1.5, .{ .x = 0.1, .y = -0.1 }, 0.1, 100, false);
    const fit = P.createFitAabb(Box{ .position = .{ .x = -1, .y = -1, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 1 } });
    const correction = P.createDepthCorrection(true);

    std.mem.doNotOptimizeAway(perspective.determinant());
    std.mem.doNotOptimizeAway(perspective.perspectiveZnearAdjusted(0.2));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.near));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.far));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.left));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.top));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.right));
    std.mem.doNotOptimizeAway(perspective.getProjectionPlane(.bottom));
    std.mem.doNotOptimizeAway(perspective.flippedY());
    std.mem.doNotOptimizeAway(perspective.jitterOffseted(.{ .x = 1, .y = 2 }));
    std.mem.doNotOptimizeAway(P.getFovy(60, 1.5));
    std.mem.doNotOptimizeAway(perspective.getZFar());
    std.mem.doNotOptimizeAway(perspective.getZNear());
    std.mem.doNotOptimizeAway(perspective.getAspect());
    std.mem.doNotOptimizeAway(perspective.getFov());
    std.mem.doNotOptimizeAway(perspective.isOrthogonal());
    std.mem.doNotOptimizeAway(perspective.getViewportHalfExtents());
    std.mem.doNotOptimizeAway(perspective.getFarPlaneHalfExtents());
    std.mem.doNotOptimizeAway(perspective.inverse());
    std.mem.doNotOptimizeAway(perspective.getPixelsPerMeter(1920));
    std.mem.doNotOptimizeAway(perspective.getLodMultiplier());
    std.mem.doNotOptimizeAway(perspective.xform(.{ .x = 1, .y = 2, .z = -1, .w = 1 }));
    std.mem.doNotOptimizeAway(perspective.xformInv(.{ .x = 1, .y = 2, .z = -1, .w = 1 }));
    std.mem.doNotOptimizeAway(perspective.xformVector3(.{ .x = 1, .y = 2, .z = -1 }));
    std.mem.doNotOptimizeAway(perspective.xformPlane(Plane.init(.{ .x = 0, .y = 1, .z = 0 }, 0)));
    std.mem.doNotOptimizeAway(perspective.mul(orthogonal));

    _ = .{ hmd, for_hmd, orthogonal_aspect, frustum, frustum_aspect, fit, correction, atlas };
}

test "Projection double precision" {
    const P = projection_mod.double.Projection;
    const perspective = P.createPerspective(60, 1, 0.1, 100, false);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), perspective.getZNear(), 1e-9);
}

const std = @import("std");

const godot = @import("godot");
const aabb_mod = godot.builtins.aabb;
const plane_mod = godot.builtins.plane;
const projection_mod = godot.builtins.projection;
const rect_mod = godot.builtins.rect;
const vector = godot.builtins.vector;
