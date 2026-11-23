//! Tests for the pure-Zig `AABB` builtin.

test "AABB end member" {
    const Box = aabb.single.AABB;
    var box = Box{ .position = .{ .x = 1, .y = 2, .z = 3 }, .size = .{ .x = 4, .y = 5, .z = 6 } };
    try std.testing.expectEqual(vector.single.Vector3{ .x = 5, .y = 7, .z = 9 }, box.getEnd());
    box.setEnd(.{ .x = 10, .y = 20, .z = 30 });
    try std.testing.expectEqual(vector.single.Vector3{ .x = 9, .y = 18, .z = 27 }, box.size);
}

test "AABB layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(aabb.single.AABB));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(aabb.double.AABB));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(aabb.single.AABB));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(aabb.double.AABB));
    try std.testing.expectEqual(aabb.single.AABB{}, aabb.single.AABB{ .position = .zero, .size = .zero });
}

test "AABB basic queries" {
    const Box = aabb.single.AABB;
    const a = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 4, .z = 6 } };

    try std.testing.expectEqual(@as(f32, 48), a.getVolume());
    try std.testing.expect(a.hasVolume());
    try std.testing.expect(a.hasSurface());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, a.getCenter());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 2, .y = 4, .z = 6 }, a.getEnd());
    try std.testing.expect(a.hasPoint(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(a.hasPoint(.{ .x = 2, .y = 4, .z = 6 }));
    try std.testing.expect(!a.hasPoint(.{ .x = -0.1, .y = 0, .z = 0 }));
    try std.testing.expect(a.isFinite());

    try std.testing.expectEqual(@as(usize, 2), a.getLongestAxisIndex());
    try std.testing.expectEqual(@as(f32, 6), a.getLongestAxisSize());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 0, .y = 0, .z = 1 }, a.getLongestAxis());
    try std.testing.expectEqual(@as(usize, 0), a.getShortestAxisIndex());
    try std.testing.expectEqual(@as(f32, 2), a.getShortestAxisSize());
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 0, .z = 0 }, a.getShortestAxis());
}

test "AABB intersection and merge" {
    const Box = aabb.single.AABB;
    const a = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 2 } };
    const b = Box{ .position = .{ .x = 1, .y = 1, .z = 1 }, .size = .{ .x = 2, .y = 2, .z = 2 } };
    const c = Box{ .position = .{ .x = 5, .y = 5, .z = 5 }, .size = .{ .x = 1, .y = 1, .z = 1 } };

    try std.testing.expect(a.intersects(b));
    try std.testing.expect(!a.intersects(c));
    try std.testing.expect(!a.encloses(b));
    try std.testing.expect(a.encloses(a));

    const intersection = a.intersection(b);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 1, .z = 1 }, intersection.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 1, .z = 1 }, intersection.size);
    try std.testing.expectEqual(Box{}, a.intersection(c));

    const merged = a.merge(b);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 0, .y = 0, .z = 0 }, merged.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 3, .y = 3, .z = 3 }, merged.size);

    const expanded = a.expand(.{ .x = -1, .y = 1, .z = 4 });
    try std.testing.expectEqual(vector.single.Vector3{ .x = -1, .y = 0, .z = 0 }, expanded.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 3, .y = 2, .z = 4 }, expanded.size);

    const grown = a.grow(1);
    try std.testing.expectEqual(vector.single.Vector3{ .x = -1, .y = -1, .z = -1 }, grown.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 4, .y = 4, .z = 4 }, grown.size);
}

test "AABB support, endpoints, abs" {
    const Box = aabb.single.AABB;
    const a = Box{ .position = .{ .x = 1, .y = 2, .z = 3 }, .size = .{ .x = 4, .y = 5, .z = 6 } };

    try std.testing.expectEqual(vector.single.Vector3{ .x = 5, .y = 7, .z = 9 }, a.getSupport(.{ .x = 1, .y = 1, .z = 1 }));
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, a.getSupport(.{ .x = -1, .y = -1, .z = -1 }));

    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 2, .z = 3 }, a.getEndpoint(0));
    try std.testing.expectEqual(vector.single.Vector3{ .x = 5, .y = 7, .z = 9 }, a.getEndpoint(7));

    const negative = Box{ .position = .{ .x = 10, .y = 10, .z = 10 }, .size = .{ .x = -4, .y = -6, .z = -2 } };
    const positive = negative.abs();
    try std.testing.expectEqual(vector.single.Vector3{ .x = 6, .y = 4, .z = 8 }, positive.position);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 4, .y = 6, .z = 2 }, positive.size);
}

test "AABB segment and ray intersection" {
    const Box = aabb.single.AABB;
    const box = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 2 } };

    const segment_hit = box.intersectsSegment(.{ .x = -1, .y = 1, .z = 1 }, .{ .x = 3, .y = 1, .z = 1 });
    try std.testing.expect(segment_hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), segment_hit.?.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), segment_hit.?.y, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), segment_hit.?.z, 0.00001);

    try std.testing.expect(box.intersectsSegment(.{ .x = -1, .y = -1, .z = -1 }, .{ .x = -2, .y = -2, .z = -2 }) == null);

    const ray_hit = box.intersectsRay(.{ .x = -1, .y = 1, .z = 1 }, .{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expect(ray_hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), ray_hit.?.x, 0.00001);

    const inside_hit = box.intersectsRay(.{ .x = 1, .y = 1, .z = 1 }, .{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expect(inside_hit != null);
    try std.testing.expectEqual(vector.single.Vector3{ .x = 1, .y = 1, .z = 1 }, inside_hit.?);

    try std.testing.expect(box.intersectsRay(.{ .x = -1, .y = -1, .z = -1 }, .{ .x = -1, .y = 0, .z = 0 }) == null);
}

test "double precision AABB" {
    const Box = aabb.double.AABB;
    const a = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 2 } };
    const b = Box{ .position = .{ .x = 1, .y = 1, .z = 1 }, .size = .{ .x = 2, .y = 2, .z = 2 } };

    try std.testing.expect(a.intersects(b));
    try std.testing.expectEqual(@as(f64, 8), a.getVolume());
    try std.testing.expectEqual(vector.double.Vector3{ .x = 1, .y = 1, .z = 1 }, a.getCenter());
}

const std = @import("std");

const godot = @import("godot");
const aabb = godot.builtins.aabb;
const vector = godot.builtins.vector;
