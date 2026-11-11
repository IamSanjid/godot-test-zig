//! Pure-Zig implementation of Godot's `Transform2D` builtin.
//!
//! Follows `core/math/transform_2d.{h,cpp}`. Operators are intentionally not
//! exposed as named methods yet; only the extension-API method set is provided.

pub fn Transform2dOf(comptime Real: type) type {
    const V2 = vector.Vector(Real, 2);
    const C = constants.For(Real);

    return extern struct {
        columns: [3]V2 = .{
            .{ .x = 1, .y = 0 },
            .{ .x = 0, .y = 1 },
            .{ .x = 0, .y = 0 },
        },

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Transform2D {
            return @as(*const bindings.builtins.Transform2D, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Transform2D => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Transform2D => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Transform2D => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Transform2D by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub const identity: Self = .{};
        pub const flipX: Self = .{ .columns = .{
            .{ .x = -1, .y = 0 },
            .{ .x = 0, .y = 1 },
            .{ .x = 0, .y = 0 },
        } };
        pub const flipY: Self = .{ .columns = .{
            .{ .x = 1, .y = 0 },
            .{ .x = 0, .y = -1 },
            .{ .x = 0, .y = 0 },
        } };

        pub fn initColumns(x_axis: V2, y_axis: V2, origin: V2) Self {
            return .{ .columns = .{ x_axis, y_axis, origin } };
        }

        pub fn inverse(self: Self) Self {
            var result = self;
            const tmp = result.columns[0].y;
            result.columns[0].y = result.columns[1].x;
            result.columns[1].x = tmp;
            result.columns[2] = result.basisXform(self.columns[2].negate());
            return result;
        }

        pub fn affineInverse(self: Self) Self {
            const det = self.determinant();
            const inverse_det = 1 / det;

            var result = self;
            const tmp = result.columns[0].x;
            result.columns[0].x = result.columns[1].y;
            result.columns[1].y = tmp;

            result.columns[0] = result.columns[0].mul(.{ .x = inverse_det, .y = -inverse_det });
            result.columns[1] = result.columns[1].mul(.{ .x = -inverse_det, .y = inverse_det });
            result.columns[2] = result.basisXform(self.columns[2].negate());
            return result;
        }

        pub fn getRotation(self: Self) Real {
            return std.math.atan2(self.columns[0].y, self.columns[0].x);
        }

        pub fn getOrigin(self: Self) V2 {
            return self.columns[2];
        }

        pub fn setOrigin(self: *Self, value: V2) void {
            self.columns[2] = value;
        }

        pub fn getX(self: Self) V2 {
            return self.columns[0];
        }

        pub fn setX(self: *Self, value: V2) void {
            self.columns[0] = value;
        }

        pub fn getY(self: Self) V2 {
            return self.columns[1];
        }

        pub fn setY(self: *Self, value: V2) void {
            self.columns[1] = value;
        }

        pub fn getScale(self: Self) V2 {
            const det = self.determinant();
            const sign: Real = if (det < 0) -1 else if (det > 0) 1 else 0;
            return .{
                .x = self.columns[0].length(),
                .y = sign * self.columns[1].length(),
            };
        }

        pub fn getSkew(self: Self) Real {
            const det = self.determinant();
            const sign: Real = if (det < 0) -1 else if (det > 0) 1 else 0;
            return std.math.acos(self.columns[0].normalized().dot(self.columns[1].normalized().scale(sign))) - std.math.pi * 0.5;
        }

        pub fn orthonormalized(self: Self) Self {
            var result = self;
            const x = result.columns[0].normalized();
            const y = result.columns[1].sub(x.scale(x.dot(result.columns[1]))).normalized();
            result.columns[0] = x;
            result.columns[1] = y;
            return result;
        }

        pub fn rotated(self: Self, angle: Real) Self {
            return compose(fromRotation(angle), self);
        }

        pub fn rotatedLocal(self: Self, angle: Real) Self {
            return compose(self, fromRotation(angle));
        }

        pub fn scaled(self: Self, scale_value: V2) Self {
            var result = self;
            result.columns[0].x *= scale_value.x;
            result.columns[0].y *= scale_value.y;
            result.columns[1].x *= scale_value.x;
            result.columns[1].y *= scale_value.y;
            result.columns[2] = result.columns[2].mul(scale_value);
            return result;
        }

        pub fn scaledLocal(self: Self, scale_value: V2) Self {
            return .{ .columns = .{
                self.columns[0].scale(scale_value.x),
                self.columns[1].scale(scale_value.y),
                self.columns[2],
            } };
        }

        pub fn translated(self: Self, offset: V2) Self {
            return .{ .columns = .{
                self.columns[0],
                self.columns[1],
                self.columns[2].add(offset),
            } };
        }

        pub fn translatedLocal(self: Self, offset: V2) Self {
            return .{ .columns = .{
                self.columns[0],
                self.columns[1],
                self.columns[2].add(self.basisXform(offset)),
            } };
        }

        pub fn determinant(self: Self) Real {
            return self.columns[0].x * self.columns[1].y - self.columns[0].y * self.columns[1].x;
        }

        pub fn basisXform(self: Self, vector_value: V2) V2 {
            return .{
                .x = self.columns[0].x * vector_value.x + self.columns[1].x * vector_value.y,
                .y = self.columns[0].y * vector_value.x + self.columns[1].y * vector_value.y,
            };
        }

        pub fn basisXformInv(self: Self, vector_value: V2) V2 {
            return .{
                .x = self.columns[0].dot(vector_value),
                .y = self.columns[1].dot(vector_value),
            };
        }

        pub fn interpolateWith(self: Self, other: Self, weight: Real) Self {
            return fromRotationScaleSkew(
                lerpAngle(self.getRotation(), other.getRotation(), weight),
                self.getScale().lerp(other.getScale(), weight),
                lerpAngle(self.getSkew(), other.getSkew(), weight),
                self.getOrigin().lerp(other.getOrigin(), weight),
            );
        }

        pub fn isConformal(self: Self) bool {
            if (isEqualApproxScalar(self.columns[0].x, self.columns[1].y) and
                isEqualApproxScalar(self.columns[0].y, -self.columns[1].x))
            {
                return true;
            }
            if (isEqualApproxScalar(self.columns[0].x, -self.columns[1].y) and
                isEqualApproxScalar(self.columns[0].y, self.columns[1].x))
            {
                return true;
            }
            return false;
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.columns[0].isEqualApprox(other.columns[0]) and
                self.columns[1].isEqualApprox(other.columns[1]) and
                self.columns[2].isEqualApprox(other.columns[2]);
        }

        pub fn isFinite(self: Self) bool {
            return self.columns[0].isFinite() and
                self.columns[1].isFinite() and
                self.columns[2].isFinite();
        }

        pub fn lookingAt(self: Self, target: V2) Self {
            var result = fromRotation(self.getRotation());
            result.columns[2] = self.getOrigin();

            const target_position = self.xformInv(target);
            const angle = target_position.mul(self.getScale()).angle();
            result.setRotation(result.getRotation() + angle);
            return result;
        }

        fn fromRotation(angle: Real) Self {
            const cosine = @cos(angle);
            const sine = @sin(angle);
            return .{ .columns = .{
                .{ .x = cosine, .y = sine },
                .{ .x = -sine, .y = cosine },
                .{ .x = 0, .y = 0 },
            } };
        }

        fn fromRotationScaleSkew(rotation: Real, scale_value: V2, skew: Real, origin: V2) Self {
            return .{ .columns = .{
                .{
                    .x = @cos(rotation) * scale_value.x,
                    .y = @sin(rotation) * scale_value.x,
                },
                .{
                    .x = -@sin(rotation + skew) * scale_value.y,
                    .y = @cos(rotation + skew) * scale_value.y,
                },
                origin,
            } };
        }

        fn setRotation(self: *Self, rotation: Real) void {
            const scale_value = self.getScale();
            const cosine = @cos(rotation);
            const sine = @sin(rotation);
            self.columns[0] = .{ .x = cosine, .y = sine };
            self.columns[1] = .{ .x = -sine, .y = cosine };
            self.setScale(scale_value);
        }

        fn setScale(self: *Self, scale_value: V2) void {
            self.columns[0] = self.columns[0].normalized().mul(.{ .x = scale_value.x, .y = scale_value.x });
            self.columns[1] = self.columns[1].normalized().mul(.{ .x = scale_value.y, .y = scale_value.y });
        }

        fn xform(self: Self, vector_value: V2) V2 {
            return self.basisXform(vector_value).add(self.columns[2]);
        }

        fn xformInv(self: Self, vector_value: V2) V2 {
            return self.basisXformInv(vector_value.sub(self.columns[2]));
        }

        fn compose(left: Self, right: Self) Self {
            var result: Self = undefined;
            result.columns[2] = left.xform(right.columns[2]);

            const x0 = left.columns[0].x * right.columns[0].x + left.columns[1].x * right.columns[0].y;
            const x1 = left.columns[0].y * right.columns[0].x + left.columns[1].y * right.columns[0].y;
            const y0 = left.columns[0].x * right.columns[1].x + left.columns[1].x * right.columns[1].y;
            const y1 = left.columns[0].y * right.columns[1].x + left.columns[1].y * right.columns[1].y;

            result.columns[0] = .{ .x = x0, .y = x1 };
            result.columns[1] = .{ .x = y0, .y = y1 };
            return result;
        }

        fn lerpAngle(from: Real, to: Real, weight: Real) Real {
            const tau = 2 * std.math.pi;
            const difference = @rem(to - from, tau);
            return from + (@rem(2 * difference, tau) - difference) * weight;
        }

        fn isEqualApproxScalar(a: Real, b: Real) bool {
            if (a == b) return true;
            var tolerance: Real = C.cmp_epsilon * @abs(a);
            if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
            return @abs(a - b) < tolerance;
        }
    };
}

pub const single = struct {
    pub const Transform2D = Transform2dOf(f32);
};

pub const double = struct {
    pub const Transform2D = Transform2dOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Transform2D = precision.Transform2D;

test "Transform2D member aliases" {
    const T = single.Transform2D;
    var xform = T.identity;
    xform.setX(.{ .x = 1, .y = 2 });
    xform.setY(.{ .x = 3, .y = 4 });
    xform.setOrigin(.{ .x = 5, .y = 6 });
    try std.testing.expectEqual(vector.single.Vector2{ .x = 1, .y = 2 }, xform.getX());
    try std.testing.expectEqual(vector.single.Vector2{ .x = 3, .y = 4 }, xform.getY());
    try std.testing.expectEqual(vector.single.Vector2{ .x = 5, .y = 6 }, xform.getOrigin());
}

test "Transform2D layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(single.Transform2D));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(double.Transform2D));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Transform2D));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Transform2D));
}

test "Transform2D basics" {
    const T = single.Transform2D;
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
    const T = single.Transform2D;
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
    const T = single.Transform2D;

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
    const T = double.Transform2D;
    const rotation = T.identity.rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotation.determinant(), 1e-12);
    const scale = T.identity.scaled(.{ .x = 2, .y = 3 }).getScale();
    try std.testing.expectEqual(vector.double.Vector2{ .x = 2, .y = 3 }, scale);
}

const std = @import("std");
const bindings = @import("bindings");
const vector = @import("vector.zig");
const constants = @import("constants.zig");
