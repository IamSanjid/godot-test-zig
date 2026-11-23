//! Pure-Zig implementation of Godot's `Plane` builtin.
//!
//! `intersect_3`, `intersects_ray`, and `intersects_segment` are adapted to
//! return `?Vector3` instead of Godot's `Variant`; `null` means no intersection.

pub fn PlaneOf(comptime Real: type) type {
    const V3 = vector.Vector(Real, 3);
    const C = constants.For(Real);

    return extern struct {
        pub const GodotClassName = "Plane";

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

        pub inline fn bindingCall(
            self: *Self,
            comptime method: @EnumLiteral(),
            args: reflect.FunctionArgsAsTupleSkipFirst(reflect.FunctionOf(generated_namespace.MemberFunctions, method)),
        ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
            const func = reflect.FunctionOf(generated_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallConst(
            self: *const Self,
            comptime method: @EnumLiteral(),
            args: reflect.FunctionArgsAsTupleSkipFirst(reflect.FunctionOf(generated_namespace.MemberFunctions, method)),
        ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
            const func = reflect.FunctionOf(generated_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallStatic(
            comptime method: @EnumLiteral(),
            args: reflect.FunctionArgsAsTuple(reflect.FunctionOf(generated_namespace.StaticFunctions, method)),
        ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
            const func = reflect.FunctionOf(generated_namespace, method);
            return @call(.auto, func, args);
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

const std = @import("std");

const bindings = @import("bindings");

const reflect = @import("../reflect/reflect.zig");
const constants = @import("constants.zig");
const generated_namespace = @import("generated/plane.zig");
const vector = @import("vector.zig");
