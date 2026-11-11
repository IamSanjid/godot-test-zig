//! Pure-Zig implementation of Godot's `Plane` builtin.
//!
//! `intersect_3`, `intersects_ray`, and `intersects_segment` are adapted to
//! return `?Vector3` instead of Godot's `Variant`; `null` means no intersection.

pub fn PlaneOf(comptime Real: type) type {
    const V3 = vector.Vector(Real, 3);
    const C = constants.For(Real);

    return extern struct {
        normal: V3 = .zero,
        d: Real = 0,

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Plane {
            return @as(*const bindings.builtins.Plane, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Plane => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Plane => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Plane => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Plane by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub const planeYZ: Self = .{ .normal = .{ .x = 1, .y = 0, .z = 0 }, .d = 0 };
        pub const planeXZ: Self = .{ .normal = .{ .x = 0, .y = 1, .z = 0 }, .d = 0 };
        pub const planeXY: Self = .{ .normal = .{ .x = 0, .y = 0, .z = 1 }, .d = 0 };

        pub fn init(normal_value: V3, d_value: Real) Self {
            return .{ .normal = normal_value, .d = d_value };
        }

        pub fn fromPointNormal(normal_value: V3, point: V3) Self {
            return .{ .normal = normal_value, .d = normal_value.dot(point) };
        }

        pub fn fromPoints(a: V3, b: V3, c: V3) Self {
            const normal_value = a.sub(c).cross(a.sub(b)).normalized();
            return .{ .normal = normal_value, .d = normal_value.dot(a) };
        }

        pub fn negate(self: Self) Self {
            return .{ .normal = self.normal.negate(), .d = -self.d };
        }

        pub fn normalized(self: Self) Self {
            const length = self.normal.length();
            if (length == 0) return .{};
            return .{ .normal = self.normal.scale(1 / length), .d = self.d / length };
        }

        pub fn getCenter(self: Self) V3 {
            return self.normal.scale(self.d);
        }

        pub fn getX(self: Self) Real {
            return self.normal.x;
        }

        pub fn setX(self: *Self, value: Real) void {
            self.normal.x = value;
        }

        pub fn getY(self: Self) Real {
            return self.normal.y;
        }

        pub fn setY(self: *Self, value: Real) void {
            self.normal.y = value;
        }

        pub fn getZ(self: Self) Real {
            return self.normal.z;
        }

        pub fn setZ(self: *Self, value: Real) void {
            self.normal.z = value;
        }

        pub fn isPointOver(self: Self, point: V3) bool {
            return self.normal.dot(point) > self.d;
        }

        pub fn distanceTo(self: Self, point: V3) Real {
            return self.normal.dot(point) - self.d;
        }

        pub fn hasPoint(self: Self, point: V3, tolerance: Real) bool {
            return @abs(self.normal.dot(point) - self.d) <= tolerance;
        }

        pub fn project(self: Self, point: V3) V3 {
            return point.sub(self.normal.scale(self.distanceTo(point)));
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.normal.isEqualApprox(other.normal) and isEqualApproxScalar(self.d, other.d);
        }

        pub fn isEqualApproxAnySide(self: Self, other: Self) bool {
            return (self.normal.isEqualApprox(other.normal) and isEqualApproxScalar(self.d, other.d)) or
                (self.normal.isEqualApprox(other.normal.negate()) and isEqualApproxScalar(self.d, -other.d));
        }

        pub fn isFinite(self: Self) bool {
            return self.normal.isFinite() and std.math.isFinite(self.d);
        }

        /// Intersection of three planes, or null when they are parallel.
        pub fn intersect3(self: Self, plane1: Self, plane2: Self) ?V3 {
            const denominator = self.normal.cross(plane1.normal).dot(plane2.normal);
            if (isZeroApprox(denominator)) return null;

            return plane1.normal.cross(plane2.normal).scale(self.d)
                .add(plane2.normal.cross(self.normal).scale(plane1.d))
                .add(self.normal.cross(plane1.normal).scale(plane2.d))
                .scale(1 / denominator);
        }

        pub fn intersectsRay(self: Self, from: V3, direction: V3) ?V3 {
            const denominator = self.normal.dot(direction);
            if (isZeroApprox(denominator)) return null;

            var distance = (self.normal.dot(from) - self.d) / denominator;
            if (distance > C.cmp_epsilon) return null;

            distance = -distance;
            return from.add(direction.scale(distance));
        }

        pub fn intersectsSegment(self: Self, begin: V3, end: V3) ?V3 {
            const segment = begin.sub(end);
            const denominator = self.normal.dot(segment);
            if (isZeroApprox(denominator)) return null;

            var distance = (self.normal.dot(begin) - self.d) / denominator;
            if (distance < -C.cmp_epsilon or distance > 1 + C.cmp_epsilon) return null;

            distance = -distance;
            return begin.add(segment.scale(distance));
        }

        /// Applies the `Plane * Transform3D` operator (inverse transform).
        pub fn transformed(self: Self, xform: anytype) Self {
            const basis_inverse = xform.basis.inverse();
            const point = basis_inverse.xform(self.normal.scale(self.d).sub(xform.origin));
            const normal_value = xform.basis.transposed().xform(self.normal).normalized();
            return .{ .normal = normal_value, .d = normal_value.dot(point) };
        }

        fn isEqualApproxScalar(a: Real, b: Real) bool {
            if (a == b) return true;
            var tolerance: Real = C.cmp_epsilon * @abs(a);
            if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
            return @abs(a - b) < tolerance;
        }

        fn isZeroApprox(value: Real) bool {
            return @abs(value) < C.cmp_epsilon;
        }
    };
}

pub const single = struct {
    pub const Plane = PlaneOf(f32);
};

pub const double = struct {
    pub const Plane = PlaneOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Plane = precision.Plane;

test "Plane component members" {
    const P = single.Plane;
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
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Plane));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(double.Plane));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Plane));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Plane));
}

test "Plane basics" {
    const P = single.Plane;
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
    const P = single.Plane;
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
    const P = single.Plane;
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
        .basis = basis.single.Basis.identity,
        .origin = vector.single.Vector3{ .x = 2, .y = 0, .z = 0 },
    };
    std.mem.doNotOptimizeAway(a.transformed(xform));
}

test "Plane double precision" {
    const P = double.Plane;
    const plane = P.init(.{ .x = 0, .y = 1, .z = 0 }, 2);
    try std.testing.expectApproxEqAbs(@as(f64, 3), plane.distanceTo(.{ .x = 0, .y = 5, .z = 0 }), 1e-12);
}

const std = @import("std");
const bindings = @import("bindings");
const vector = @import("vector.zig");
const basis = @import("basis.zig");
const constants = @import("constants.zig");
