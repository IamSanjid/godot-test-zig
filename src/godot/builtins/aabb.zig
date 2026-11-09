//! Pure-Zig implementation of Godot's `AABB` builtin.
//!
//! An AABB is a position plus a size, both `Vector3`s. The math here mirrors
//! `core/math/aabb.{h,cpp}`. The computed `end` member is exposed as
//! `getEnd`/`setEnd`, matching Godot's `get_end`/`set_end` accessors.
//!
//! `intersects_segment` and `intersects_ray` are exposed as `?Vector3` instead
//! of Godot's `Variant` return: `null` means "no intersection".

pub fn AabbOf(comptime Real: type) type {
    const V3 = vector.Vector(Real, 3);

    return extern struct {
        position: V3 = .zero,
        size: V3 = .zero,

        const Self = @This();

        pub fn init(position: V3, size: V3) Self {
            return .{ .position = position, .size = size };
        }

        pub fn getEnd(self: Self) V3 {
            return self.position.add(self.size);
        }

        pub fn setEnd(self: *Self, end: V3) void {
            self.size = end.sub(self.position);
        }

        pub fn getCenter(self: Self) V3 {
            return self.position.add(self.size.scale(0.5));
        }

        pub fn getVolume(self: Self) Real {
            return self.size.x * self.size.y * self.size.z;
        }

        pub fn hasVolume(self: Self) bool {
            return self.size.x > 0 and self.size.y > 0 and self.size.z > 0;
        }

        pub fn hasSurface(self: Self) bool {
            return self.size.x > 0 or self.size.y > 0 or self.size.z > 0;
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.position.isEqualApprox(other.position) and self.size.isEqualApprox(other.size);
        }

        pub fn isFinite(self: Self) bool {
            return self.position.isFinite() and self.size.isFinite();
        }

        pub fn hasPoint(self: Self, point: V3) bool {
            return point.x >= self.position.x and
                point.y >= self.position.y and
                point.z >= self.position.z and
                point.x <= self.position.x + self.size.x and
                point.y <= self.position.y + self.size.y and
                point.z <= self.position.z + self.size.z;
        }

        /// Both boxes overlap. Touching faces do not count.
        pub fn intersects(self: Self, other: Self) bool {
            const end = self.position.add(self.size);
            const other_end = other.position.add(other.size);

            return self.position.x < other_end.x and end.x > other.position.x and
                self.position.y < other_end.y and end.y > other.position.y and
                self.position.z < other_end.z and end.z > other.position.z;
        }

        /// `other` is completely inside this box.
        pub fn encloses(self: Self, other: Self) bool {
            const end = self.position.add(self.size);
            const other_end = other.position.add(other.size);

            return self.position.x <= other.position.x and end.x >= other_end.x and
                self.position.y <= other.position.y and end.y >= other_end.y and
                self.position.z <= other.position.z and end.z >= other_end.z;
        }

        /// Returns an empty AABB if the boxes do not overlap.
        pub fn intersection(self: Self, other: Self) Self {
            const end = self.position.add(self.size);
            const other_end = other.position.add(other.size);

            if (self.position.x > other_end.x or end.x < other.position.x or
                self.position.y > other_end.y or end.y < other.position.y or
                self.position.z > other_end.z or end.z < other.position.z)
            {
                return .{};
            }

            const min = V3{
                .x = @max(self.position.x, other.position.x),
                .y = @max(self.position.y, other.position.y),
                .z = @max(self.position.z, other.position.z),
            };
            const max = V3{
                .x = @min(end.x, other_end.x),
                .y = @min(end.y, other_end.y),
                .z = @min(end.z, other_end.z),
            };
            return .{ .position = min, .size = max.sub(min) };
        }

        pub fn merge(self: Self, other: Self) Self {
            const end = self.position.add(self.size);
            const other_end = other.position.add(other.size);

            const min = V3{
                .x = @min(self.position.x, other.position.x),
                .y = @min(self.position.y, other.position.y),
                .z = @min(self.position.z, other.position.z),
            };
            const max = V3{
                .x = @max(end.x, other_end.x),
                .y = @max(end.y, other_end.y),
                .z = @max(end.z, other_end.z),
            };
            return .{ .position = min, .size = max.sub(min) };
        }

        pub fn expand(self: Self, point: V3) Self {
            const begin = V3{
                .x = @min(self.position.x, point.x),
                .y = @min(self.position.y, point.y),
                .z = @min(self.position.z, point.z),
            };
            const end = self.position.add(self.size);
            const new_end = V3{
                .x = @max(end.x, point.x),
                .y = @max(end.y, point.y),
                .z = @max(end.z, point.z),
            };
            return .{ .position = begin, .size = new_end.sub(begin) };
        }

        pub fn grow(self: Self, by: Real) Self {
            return .{
                .position = self.position.sub(V3{ .x = by, .y = by, .z = by }),
                .size = self.size.add(V3{ .x = by * 2, .y = by * 2, .z = by * 2 }),
            };
        }

        pub fn getSupport(self: Self, direction: V3) V3 {
            return .{
                .x = self.position.x + if (direction.x > 0) self.size.x else 0,
                .y = self.position.y + if (direction.y > 0) self.size.y else 0,
                .z = self.position.z + if (direction.z > 0) self.size.z else 0,
            };
        }

        pub fn getLongestAxis(self: Self) V3 {
            if (self.size.y > self.size.x) {
                if (self.size.z > self.size.y) return .{ .x = 0, .y = 0, .z = 1 };
                return .{ .x = 0, .y = 1, .z = 0 };
            }
            if (self.size.z > self.size.x) return .{ .x = 0, .y = 0, .z = 1 };
            return .{ .x = 1, .y = 0, .z = 0 };
        }

        pub fn getLongestAxisIndex(self: Self) usize {
            var axis: usize = 0;
            var max_size = self.size.x;
            if (self.size.y > max_size) {
                axis = 1;
                max_size = self.size.y;
            }
            if (self.size.z > max_size) axis = 2;
            return axis;
        }

        pub fn getLongestAxisSize(self: Self) Real {
            return @max(self.size.x, @max(self.size.y, self.size.z));
        }

        pub fn getShortestAxis(self: Self) V3 {
            if (self.size.y < self.size.x) {
                if (self.size.z < self.size.y) return .{ .x = 0, .y = 0, .z = 1 };
                return .{ .x = 0, .y = 1, .z = 0 };
            }
            if (self.size.z < self.size.x) return .{ .x = 0, .y = 0, .z = 1 };
            return .{ .x = 1, .y = 0, .z = 0 };
        }

        pub fn getShortestAxisIndex(self: Self) usize {
            var axis: usize = 0;
            var min_size = self.size.x;
            if (self.size.y < min_size) {
                axis = 1;
                min_size = self.size.y;
            }
            if (self.size.z < min_size) axis = 2;
            return axis;
        }

        pub fn getShortestAxisSize(self: Self) Real {
            return @min(self.size.x, @min(self.size.y, self.size.z));
        }

        pub fn getEndpoint(self: Self, index: usize) V3 {
            const x0 = self.position.x;
            const y0 = self.position.y;
            const z0 = self.position.z;
            const x1 = x0 + self.size.x;
            const y1 = y0 + self.size.y;
            const z1 = z0 + self.size.z;

            return switch (index) {
                0 => .{ .x = x0, .y = y0, .z = z0 },
                1 => .{ .x = x0, .y = y0, .z = z1 },
                2 => .{ .x = x0, .y = y1, .z = z0 },
                3 => .{ .x = x0, .y = y1, .z = z1 },
                4 => .{ .x = x1, .y = y0, .z = z0 },
                5 => .{ .x = x1, .y = y0, .z = z1 },
                6 => .{ .x = x1, .y = y1, .z = z0 },
                7 => .{ .x = x1, .y = y1, .z = z1 },
                else => .zero,
            };
        }

        pub fn abs(self: Self) Self {
            return .{
                .position = self.position.add(self.size.minf(0)),
                .size = self.size.abs(),
            };
        }

        /// True when the plane cuts through the box.
        pub fn intersectsPlane(self: Self, plane_value: plane.PlaneOf(Real)) bool {
            var over = false;
            var under = false;

            inline for (0..8) |i| {
                if (plane_value.distanceTo(self.getEndpoint(i)) > 0) {
                    over = true;
                } else {
                    under = true;
                }
            }

            return over and under;
        }

        /// Transforms this box by a `Transform3D`-like value (anything with
        /// `basis.rows` and `origin` fields). Equivalent to Godot's
        /// `AABB * Transform3D` operator.
        pub fn transformed(self: Self, xform: anytype) Self {
            const min = self.position;
            const max = self.position.add(self.size);

            var tmin = V3.zero;
            var tmax = V3.zero;

            inline for (0..3) |i| {
                var axis_min: Real = component(xform.origin, i);
                var axis_max: Real = axis_min;

                inline for (0..3) |j| {
                    const basis_value = component(xform.basis.rows[i], j);
                    const e = basis_value * component(min, j);
                    const f = basis_value * component(max, j);
                    if (e < f) {
                        axis_min += e;
                        axis_max += f;
                    } else {
                        axis_min += f;
                        axis_max += e;
                    }
                }

                setComponent(&tmin, i, axis_min);
                setComponent(&tmax, i, axis_max);
            }

            return .{ .position = tmin, .size = tmax.sub(tmin) };
        }

        /// Returns the entry point of the segment, or null if it misses.
        pub fn intersectsSegment(self: Self, from: V3, to: V3) ?V3 {
            var min: Real = 0;
            var max: Real = 1;
            // Only the parameter range is needed for the returned point.\r\n
            for (0..3) |i| {
                const seg_from = component(from, i);
                const seg_to = component(to, i);
                const box_begin = component(self.position, i);
                const box_end = box_begin + component(self.size, i);

                var cmin: Real = undefined;
                var cmax: Real = undefined;
                var csign: Real = undefined;

                if (seg_from < seg_to) {
                    if (seg_from > box_end or seg_to < box_begin) return null;
                    const length = seg_to - seg_from;
                    cmin = if (seg_from < box_begin) (box_begin - seg_from) / length else 0;
                    cmax = if (seg_to > box_end) (box_end - seg_from) / length else 1;
                    csign = -1;
                } else {
                    if (seg_to > box_end or seg_from < box_begin) return null;
                    const length = seg_to - seg_from;
                    cmin = if (seg_from > box_end) (box_end - seg_from) / length else 0;
                    cmax = if (seg_to < box_begin) (box_begin - seg_from) / length else 1;
                    csign = 1;
                }

                if (cmin > min) min = cmin;
                if (cmax < max) max = cmax;
                if (max < min) return null;
            }

            return from.add(to.sub(from).scale(min));
        }

        /// Returns the ray entry point, or the ray origin when it starts inside.
        pub fn intersectsRay(self: Self, from: V3, direction: V3) ?V3 {
            const end = self.position.add(self.size);
            var tmin: Real = -1e20;
            var tmax: Real = 1e20;
            var axis: usize = 0;

            for (0..3) |i| {
                const from_i = component(from, i);
                const dir_i = component(direction, i);
                const start = component(self.position, i);
                const stop = component(end, i);

                if (dir_i == 0) {
                    if (from_i < start or from_i > stop) return null;
                } else {
                    var t1 = (start - from_i) / dir_i;
                    var t2 = (stop - from_i) / dir_i;
                    if (t1 > t2) {
                        const tmp = t1;
                        t1 = t2;
                        t2 = tmp;
                    }
                    if (t1 >= tmin) {
                        tmin = t1;
                        axis = i;
                    }
                    if (t2 < tmax) {
                        if (t2 < 0) return null;
                        tmax = t2;
                    }
                    if (tmin > tmax) return null;
                }
            }

            const inside = tmin < 0;
            if (inside) return from;

            var point = from.add(direction.scale(tmin));
            setComponent(&point, axis, if (component(direction, axis) >= 0) component(self.position, axis) else component(end, axis));
            return point;
        }
    };
}

fn component(value: anytype, index: usize) @TypeOf(value.x) {
    return switch (index) {
        0 => value.x,
        1 => value.y,
        2 => value.z,
        else => unreachable,
    };
}

fn setComponent(value: anytype, index: usize, new_value: @TypeOf(value.x)) void {
    switch (index) {
        0 => value.x = new_value,
        1 => value.y = new_value,
        2 => value.z = new_value,
        else => unreachable,
    }
}

pub const single = struct {
    pub const AABB = AabbOf(f32);
};

pub const double = struct {
    pub const AABB = AabbOf(f64);
};

/// Default single-precision alias. As with `vector.zig`, precision selection can
/// be exported from a build-configuration-aware module later.
pub const AABB = single.AABB;

test "AABB end member" {
    const Box = single.AABB;
    var box = Box{ .position = .{ .x = 1, .y = 2, .z = 3 }, .size = .{ .x = 4, .y = 5, .z = 6 } };
    try std.testing.expectEqual(vector.single.Vector3{ .x = 5, .y = 7, .z = 9 }, box.getEnd());
    box.setEnd(.{ .x = 10, .y = 20, .z = 30 });
    try std.testing.expectEqual(vector.single.Vector3{ .x = 9, .y = 18, .z = 27 }, box.size);
}

test "AABB layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(single.AABB));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(double.AABB));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.AABB));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.AABB));
    try std.testing.expectEqual(single.AABB{}, single.AABB{ .position = .zero, .size = .zero });
}

test "AABB basic queries" {
    const Box = single.AABB;
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
    const Box = single.AABB;
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
    const Box = single.AABB;
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
    const Box = single.AABB;
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
    const Box = double.AABB;
    const a = Box{ .position = .{ .x = 0, .y = 0, .z = 0 }, .size = .{ .x = 2, .y = 2, .z = 2 } };
    const b = Box{ .position = .{ .x = 1, .y = 1, .z = 1 }, .size = .{ .x = 2, .y = 2, .z = 2 } };

    try std.testing.expect(a.intersects(b));
    try std.testing.expectEqual(@as(f64, 8), a.getVolume());
    try std.testing.expectEqual(vector.double.Vector3{ .x = 1, .y = 1, .z = 1 }, a.getCenter());
}

const std = @import("std");
const vector = @import("vector.zig");
const plane = @import("plane.zig");
