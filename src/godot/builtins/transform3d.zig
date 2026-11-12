//! Pure-Zig implementation of Godot's `Transform3D` builtin.
//!
//! A `Transform3D` is a `Basis` plus an origin `Vector3`. The math follows
//! `core/math/transform_3d.{h,cpp}`. Plane and PackedVector3Array transforms
//! are deferred until those builtins exist; `interpolate_with` is deferred until
//! the Quaternion builtin exists.

pub fn Transform3dOf(comptime Real: type) type {
    const V3 = vector.Vector(Real, 3);
    const B = basis.BasisOf(Real);
    const AABB = aabb.AabbOf(Real);
    const Plane = plane.PlaneOf(Real);

    return extern struct {
        basis: B = .{},
        origin: V3 = .zero,

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Transform3D {
            return @as(*const bindings.builtins.Transform3D, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Transform3D => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Transform3D => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Transform3D => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Transform3D by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub inline fn bindingCall(
            self: *Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, method)) {
            const func = auto.FunctionOf(generated_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallConst(
            self: *const Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, method)) {
            const func = auto.FunctionOf(generated_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallStatic(
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTuple(auto.FunctionOf(generated_namespace.StaticFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, method)) {
            const func = auto.FunctionOf(generated_namespace, method);
            return @call(.auto, func, args);
        }

        pub const identity: Self = .{ .basis = B.identity, .origin = .zero };
        pub const flipX: Self = .{ .basis = B.flipX, .origin = .zero };
        pub const flipY: Self = .{ .basis = B.flipY, .origin = .zero };
        pub const flipZ: Self = .{ .basis = B.flipZ, .origin = .zero };

        pub fn init(basis_value: B, origin_value: V3) Self {
            return .{ .basis = basis_value, .origin = origin_value };
        }

        /// Inverse assuming the basis is orthonormal (rotation + reflection).
        pub fn inverse(self: Self) Self {
            var result = self;
            result.basis = self.basis.transposed();
            result.origin = result.basis.xform(self.origin.negate());
            return result;
        }

        /// Inverse that also handles scale/skew.
        pub fn affineInverse(self: Self) Self {
            var result = self;
            result.basis = self.basis.inverse();
            result.origin = result.basis.xform(self.origin.negate());
            return result;
        }

        pub fn orthonormalized(self: Self) Self {
            return .{ .basis = self.basis.orthonormalized(), .origin = self.origin };
        }

        pub fn rotated(self: Self, axis: V3, angle: Real) Self {
            const rotation = B.fromAxisAngle(axis, angle);
            return .{
                .basis = rotation.mul(self.basis),
                .origin = rotation.xform(self.origin),
            };
        }

        pub fn rotatedLocal(self: Self, axis: V3, angle: Real) Self {
            const rotation = B.fromAxisAngle(axis, angle);
            return .{
                .basis = self.basis.mul(rotation),
                .origin = self.origin,
            };
        }

        pub fn scaled(self: Self, scale: V3) Self {
            return .{
                .basis = self.basis.scaled(scale),
                .origin = self.origin.mul(scale),
            };
        }

        pub fn scaledLocal(self: Self, scale: V3) Self {
            return .{
                .basis = self.basis.scaledLocal(scale),
                .origin = self.origin,
            };
        }

        pub fn translated(self: Self, offset: V3) Self {
            return .{ .basis = self.basis, .origin = self.origin.add(offset) };
        }

        pub fn translatedLocal(self: Self, offset: V3) Self {
            return .{ .basis = self.basis, .origin = self.origin.add(self.basis.xform(offset)) };
        }

        pub fn lookingAt(self: Self, target: V3, up: V3, use_model_front: bool) Self {
            return .{
                .basis = B.lookingAt(target.sub(self.origin), up, use_model_front),
                .origin = self.origin,
            };
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.basis.isEqualApprox(other.basis) and self.origin.isEqualApprox(other.origin);
        }

        pub fn isFinite(self: Self) bool {
            return self.basis.isFinite() and self.origin.isFinite();
        }

        pub fn interpolateWith(self: Self, other: Self, weight: Real) Self {
            const src_scale = self.basis.getScale();
            const dst_scale = other.basis.getScale();
            const result_basis = B.fromQuaternion(
                self.basis.getRotationQuaternion().slerp(other.basis.getRotationQuaternion(), weight).normalized(),
            ).scaled(src_scale.lerp(dst_scale, weight));

            return .{
                .basis = result_basis,
                .origin = self.origin.lerp(other.origin, weight),
            };
        }

        pub fn xform(self: Self, vector_value: V3) V3 {
            return self.basis.xform(vector_value).add(self.origin);
        }

        pub fn xformInv(self: Self, vector_value: V3) V3 {
            const relative = vector_value.sub(self.origin);
            return .{
                .x = self.basis.rows[0].x * relative.x + self.basis.rows[1].x * relative.y + self.basis.rows[2].x * relative.z,
                .y = self.basis.rows[0].y * relative.x + self.basis.rows[1].y * relative.y + self.basis.rows[2].y * relative.z,
                .z = self.basis.rows[0].z * relative.x + self.basis.rows[1].z * relative.y + self.basis.rows[2].z * relative.z,
            };
        }

        /// The `Transform3D * Plane` operator.
        pub fn xformPlane(self: Self, plane_value: Plane) Plane {
            const inverse_transpose = self.basis.inverse().transposed();
            const point = self.xform(plane_value.normal.scale(plane_value.d));
            const normal_value = inverse_transpose.xform(plane_value.normal).normalized();
            return .{ .normal = normal_value, .d = normal_value.dot(point) };
        }

        /// Transforms an AABB, matching `Transform3D::xform(const AABB&)`.
        pub fn xformAabb(self: Self, box: AABB) AABB {
            const min = box.position;
            const max = box.position.add(box.size);

            var tmin = V3.zero;
            var tmax = V3.zero;

            inline for (0..3) |i| {
                var axis_min: Real = component(self.origin, i);
                var axis_max: Real = axis_min;

                inline for (0..3) |j| {
                    const basis_value = component(self.basis.rows[i], j);
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

        /// `self * other`.
        pub fn mul(self: Self, other: Self) Self {
            return .{
                .basis = self.basis.mul(other.basis),
                .origin = self.xform(other.origin),
            };
        }

        pub fn scaledBy(self: Self, scalar: Real) Self {
            return .{
                .basis = self.basis.scaled(.{ .x = scalar, .y = scalar, .z = scalar }),
                .origin = self.origin.scale(scalar),
            };
        }

        pub fn dividedBy(self: Self, scalar: Real) Self {
            return self.scaledBy(1 / scalar);
        }
    };
}

pub const single = struct {
    pub const Transform3D = Transform3dOf(f32);
};

pub const double = struct {
    pub const Transform3D = Transform3dOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Transform3D = precision.Transform3D;

test "Transform3D layout" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(single.Transform3D));
    try std.testing.expectEqual(@as(usize, 96), @sizeOf(double.Transform3D));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Transform3D));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Transform3D));
}

test "Transform3D transform basics" {
    const T = single.Transform3D;
    const V = vector.single.Vector3;

    try std.testing.expectEqual(V{ .x = 1, .y = 2, .z = 3 }, T.identity.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const translated = T.identity.translated(.{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(V{ .x = 2, .y = 4, .z = 6 }, translated.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const scaled = T.identity.scaled(.{ .x = 2, .y = 3, .z = 4 });
    try std.testing.expectEqual(V{ .x = 2, .y = 6, .z = 12 }, scaled.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const combined = translated.mul(scaled);
    try std.testing.expectEqual(V{ .x = 3, .y = 8, .z = 15 }, combined.xform(.{ .x = 1, .y = 2, .z = 3 }));

    try std.testing.expect(combined.mul(combined.affineInverse()).isEqualApprox(T.identity));

    const rotation = T.init(basis.single.Basis.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, 0.5), .{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expect(rotation.mul(rotation.inverse()).isEqualApprox(T.identity));
}

test "Transform3D rotation and AABB transform" {
    const T = single.Transform3D;
    const B = basis.single.Basis;
    const AABB = aabb.single.AABB;

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
    const T = single.Transform3D;
    const P = plane.single.Plane;
    const Box = aabb.single.AABB;

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
    const T = double.Transform3D;
    const translated = T.identity.translated(.{ .x = 1, .y = 2, .z = 3 });
    const transformed = translated.xform(.{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(vector.double.Vector3{ .x = 2, .y = 4, .z = 6 }, transformed);
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

const std = @import("std");
const bindings = @import("bindings");
const auto = @import("../auto/auto.zig");
const generated_namespace = @import("generated/transform3d.zig");
const vector = @import("vector.zig");
const basis = @import("basis.zig");
const aabb = @import("aabb.zig");
const plane = @import("plane.zig");
