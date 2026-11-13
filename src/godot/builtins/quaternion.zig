//! Pure-Zig implementation of Godot's `Quaternion` builtin.
//!
//! Follows `core/math/quaternion.{h,cpp}`. Methods that take an Euler order are
//! exposed in their default YXZ convention, matching Godot's `Quaternion`
//! bindings (which do not take an order).

pub fn QuaternionOf(comptime Real: type) type {
    const V3 = vector.Vector(Real, 3);
    const C = constants.For(Real);

    return extern struct {
        pub const GodotClassName = "Quaternion";

        x: Real = 0,
        y: Real = 0,
        z: Real = 0,
        w: Real = 1,

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Quaternion {
            return @as(*const bindings.builtins.Quaternion, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Quaternion => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Quaternion => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Quaternion => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Quaternion by value or a pointer to it, found: " ++ @typeName(V)),
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

        pub const identity: Self = .{ .x = 0, .y = 0, .z = 0, .w = 1 };

        pub fn init(x: Real, y: Real, z: Real, w: Real) Self {
            return .{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn fromAxisAngle(axis: V3, angle: Real) Self {
            const axis_length = axis.length();
            if (axis_length == 0) return .{ .x = 0, .y = 0, .z = 0, .w = 0 };

            const sine = @sin(angle * 0.5);
            const cosine = @cos(angle * 0.5);
            const scale_value = sine / axis_length;
            return .{
                .x = axis.x * scale_value,
                .y = axis.y * scale_value,
                .z = axis.z * scale_value,
                .w = cosine,
            };
        }

        /// YXZ Euler convention, matching `Quaternion::from_euler`.
        pub fn fromEuler(euler: V3) Self {
            const half_a1 = euler.y * 0.5;
            const half_a2 = euler.x * 0.5;
            const half_a3 = euler.z * 0.5;

            const cos_a1 = @cos(half_a1);
            const sin_a1 = @sin(half_a1);
            const cos_a2 = @cos(half_a2);
            const sin_a2 = @sin(half_a2);
            const cos_a3 = @cos(half_a3);
            const sin_a3 = @sin(half_a3);

            return .{
                .x = sin_a1 * cos_a2 * sin_a3 + cos_a1 * sin_a2 * cos_a3,
                .y = sin_a1 * cos_a2 * cos_a3 - cos_a1 * sin_a2 * sin_a3,
                .z = -sin_a1 * sin_a2 * cos_a3 + cos_a1 * cos_a2 * sin_a3,
                .w = sin_a1 * sin_a2 * sin_a3 + cos_a1 * cos_a2 * cos_a3,
            };
        }

        pub fn lengthSquared(self: Self) Real {
            return self.dot(self);
        }

        pub fn length(self: Self) Real {
            return @sqrt(self.lengthSquared());
        }

        pub fn normalized(self: Self) Self {
            return self.scale(1 / self.length());
        }

        pub fn isNormalized(self: Self) bool {
            return isEqualApproxScalarTolerance(self.lengthSquared(), 1, C.unit_epsilon);
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return isEqualApproxScalar(self.x, other.x) and
                isEqualApproxScalar(self.y, other.y) and
                isEqualApproxScalar(self.z, other.z) and
                isEqualApproxScalar(self.w, other.w);
        }

        pub fn isFinite(self: Self) bool {
            return std.math.isFinite(self.x) and
                std.math.isFinite(self.y) and
                std.math.isFinite(self.z) and
                std.math.isFinite(self.w);
        }

        pub fn inverse(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = self.w };
        }

        pub fn log(self: Self) Self {
            if (@abs(self.w) > 1 - C.cmp_epsilon) {
                return .{ .x = self.x * 2, .y = self.y * 2, .z = self.z * 2, .w = 0 };
            }

            const axis = self.getAxis();
            const angle = self.getAngle();
            return .{ .x = axis.x * angle, .y = axis.y * angle, .z = axis.z * angle, .w = 0 };
        }

        pub fn exp(self: Self) Self {
            const axis = V3{ .x = self.x, .y = self.y, .z = self.z };
            const theta = axis.length();
            const normalized_axis = axis.normalized();
            if (theta < C.cmp_epsilon or !normalized_axis.isNormalized()) {
                return identity;
            }
            return fromAxisAngle(normalized_axis, theta);
        }

        pub fn dot(self: Self, other: Self) Real {
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        pub fn angleTo(self: Self, to: Self) Real {
            const d = self.dot(to);
            return std.math.acos(std.math.clamp(d * d * 2 - 1, -1, 1));
        }

        pub fn slerp(self: Self, to: Self, weight: Real) Self {
            var cosom = self.dot(to);
            const to1 = if (cosom < 0) blk: {
                cosom = -cosom;
                break :blk to.negate();
            } else to;

            var scale0: Real = undefined;
            var scale1: Real = undefined;
            if (1 - cosom > C.cmp_epsilon) {
                const omega = std.math.acos(std.math.clamp(cosom, -1, 1));
                const sinom = @sin(omega);
                scale0 = @sin((1 - weight) * omega) / sinom;
                scale1 = @sin(weight * omega) / sinom;
            } else {
                scale0 = 1 - weight;
                scale1 = weight;
            }

            return .{
                .x = scale0 * self.x + scale1 * to1.x,
                .y = scale0 * self.y + scale1 * to1.y,
                .z = scale0 * self.z + scale1 * to1.z,
                .w = scale0 * self.w + scale1 * to1.w,
            };
        }

        pub fn slerpni(self: Self, to: Self, weight: Real) Self {
            const dot_value = self.dot(to);
            if (@abs(dot_value) > 0.9999) return self;

            const theta = std.math.acos(std.math.clamp(dot_value, -1, 1));
            const sin_theta = 1 / @sin(theta);
            const new_factor = @sin(weight * theta) * sin_theta;
            const inv_factor = @sin((1 - weight) * theta) * sin_theta;

            return .{
                .x = inv_factor * self.x + new_factor * to.x,
                .y = inv_factor * self.y + new_factor * to.y,
                .z = inv_factor * self.z + new_factor * to.z,
                .w = inv_factor * self.w + new_factor * to.w,
            };
        }

        pub fn sphericalCubicInterpolate(
            self: Self,
            b: Self,
            pre_a: Self,
            post_b: Self,
            weight: Real,
        ) Self {
            const from_q = canonical(self);
            var pre_q = canonical(pre_a);
            var to_q = canonical(b);
            var post_q = canonical(post_b);

            const flip1 = from_q.dot(pre_q) < 0;
            if (flip1) pre_q = pre_q.negate();

            const flip2 = from_q.dot(to_q) < 0;
            if (flip2) to_q = to_q.negate();

            const flip3 = if (flip2) to_q.dot(post_q) <= 0 else to_q.dot(post_q) < 0;
            if (flip3) post_q = post_q.negate();

            const blend_q = from_q.slerp(to_q, weight).normalized();

            var ln = Self{ .x = 0, .y = 0, .z = 0, .w = 0 };
            const ln_from = blend_q.inverse().mul(from_q).log();
            const ln_to = blend_q.inverse().mul(to_q).log();
            const ln_pre = blend_q.inverse().mul(pre_q).log();
            const ln_post = blend_q.inverse().mul(post_q).log();

            ln.x = cubicScalar(ln_from.x, ln_to.x, ln_pre.x, ln_post.x, weight);
            ln.y = cubicScalar(ln_from.y, ln_to.y, ln_pre.y, ln_post.y, weight);
            ln.z = cubicScalar(ln_from.z, ln_to.z, ln_pre.z, ln_post.z, weight);

            return blend_q.mul(ln.exp());
        }

        pub fn sphericalCubicInterpolateInTime(
            self: Self,
            b: Self,
            pre_a: Self,
            post_b: Self,
            weight: Real,
            b_time: Real,
            pre_a_time: Real,
            post_b_time: Real,
        ) Self {
            const from_q = canonical(self);
            var pre_q = canonical(pre_a);
            var to_q = canonical(b);
            var post_q = canonical(post_b);

            if (from_q.dot(pre_q) < 0) pre_q = pre_q.negate();
            const flip2 = from_q.dot(to_q) < 0;
            if (flip2) to_q = to_q.negate();
            if (if (flip2) to_q.dot(post_q) <= 0 else to_q.dot(post_q) < 0) post_q = post_q.negate();

            const blend_q = from_q.slerp(to_q, weight).normalized();

            var ln = Self{ .x = 0, .y = 0, .z = 0, .w = 0 };
            const ln_from = blend_q.inverse().mul(from_q).log();
            const ln_to = blend_q.inverse().mul(to_q).log();
            const ln_pre = blend_q.inverse().mul(pre_q).log();
            const ln_post = blend_q.inverse().mul(post_q).log();

            ln.x = cubicInTimeScalar(ln_from.x, ln_to.x, ln_pre.x, ln_post.x, weight, b_time, pre_a_time, post_b_time);
            ln.y = cubicInTimeScalar(ln_from.y, ln_to.y, ln_pre.y, ln_post.y, weight, b_time, pre_a_time, post_b_time);
            ln.z = cubicInTimeScalar(ln_from.z, ln_to.z, ln_pre.z, ln_post.z, weight, b_time, pre_a_time, post_b_time);

            return blend_q.mul(ln.exp());
        }

        /// Default YXZ Euler convention, matching Godot's Quaternion binding.
        pub fn getEuler(self: Self) V3 {
            const rows = self.toBasisRows();
            const epsilon = C.euler_epsilon;
            const m12 = rows[1].z;

            if (m12 < (1 - epsilon)) {
                if (m12 > -(1 - epsilon)) {
                    if (rows[1].x == 0 and rows[0].y == 0 and rows[0].z == 0 and rows[2].x == 0 and rows[0].x == 1) {
                        return .{ .x = std.math.atan2(-m12, rows[1].y), .y = 0, .z = 0 };
                    }
                    return .{
                        .x = std.math.asin(-m12),
                        .y = std.math.atan2(rows[0].z, rows[2].z),
                        .z = std.math.atan2(rows[1].x, rows[1].y),
                    };
                }
                return .{ .x = std.math.pi * 0.5, .y = std.math.atan2(rows[0].y, rows[0].x), .z = 0 };
            }
            return .{ .x = -std.math.pi * 0.5, .y = -std.math.atan2(rows[0].y, rows[0].x), .z = 0 };
        }

        pub fn getAxis(self: Self) V3 {
            if (@abs(self.w) > 1 - C.cmp_epsilon) return .{ .x = self.x, .y = self.y, .z = self.z };

            const inverse_scale = 1 / @sqrt(1 - self.w * self.w);
            return .{
                .x = self.x * inverse_scale,
                .y = self.y * inverse_scale,
                .z = self.z * inverse_scale,
            };
        }

        pub fn getAngle(self: Self) Real {
            return 2 * std.math.acos(std.math.clamp(self.w, -1, 1));
        }

        pub fn add(self: Self, other: Self) Self {
            return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = self.w + other.w };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z, .w = self.w - other.w };
        }

        pub fn negate(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = -self.w };
        }

        pub fn scale(self: Self, scalar: Real) Self {
            return .{ .x = self.x * scalar, .y = self.y * scalar, .z = self.z * scalar, .w = self.w * scalar };
        }

        pub fn dividedBy(self: Self, scalar: Real) Self {
            return self.scale(1 / scalar);
        }

        pub fn mul(self: Self, other: Self) Self {
            return .{
                .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
                .y = self.w * other.y + self.y * other.w + self.z * other.x - self.x * other.z,
                .z = self.w * other.z + self.z * other.w + self.x * other.y - self.y * other.x,
                .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            };
        }

        pub fn xform(self: Self, vector_value: V3) V3 {
            const u = V3{ .x = self.x, .y = self.y, .z = self.z };
            const uv = u.cross(vector_value);
            return vector_value.add(uv.scale(self.w).add(u.cross(uv)).scale(2));
        }

        pub fn toBasisRows(self: Self) [3]V3 {
            const x2 = self.x + self.x;
            const y2 = self.y + self.y;
            const z2 = self.z + self.z;
            const xx = self.x * x2;
            const xy = self.x * y2;
            const xz = self.x * z2;
            const yy = self.y * y2;
            const yz = self.y * z2;
            const zz = self.z * z2;
            const wx = self.w * x2;
            const wy = self.w * y2;
            const wz = self.w * z2;

            return .{
                .{ .x = 1 - (yy + zz), .y = xy - wz, .z = xz + wy },
                .{ .x = xy + wz, .y = 1 - (xx + zz), .z = yz - wx },
                .{ .x = xz - wy, .y = yz + wx, .z = 1 - (xx + yy) },
            };
        }

        /// Converts a rotation matrix (row-major) to a quaternion, matching
        /// `Basis::get_quaternion`.
        pub fn fromBasisRows(rows: [3]V3) Self {
            const trace = rows[0].x + rows[1].y + rows[2].z;
            if (trace > 0) {
                const s = @sqrt(trace + 1);
                const inverse_scale = 0.5 / s;
                return .{
                    .x = (rows[2].y - rows[1].z) * inverse_scale,
                    .y = (rows[0].z - rows[2].x) * inverse_scale,
                    .z = (rows[1].x - rows[0].y) * inverse_scale,
                    .w = s * 0.5,
                };
            }

            const i: usize = if (rows[0].x < rows[1].y)
                (if (rows[1].y < rows[2].z) 2 else 1)
            else
                (if (rows[0].x < rows[2].z) 2 else 0);
            const j = (i + 1) % 3;
            const k = (j + 1) % 3;

            const s = @sqrt(component(rows[i], i) - component(rows[j], j) - component(rows[k], k) + 1);
            const inverse_scale = 0.5 / s;

            var values = [4]Real{ 0, 0, 0, 0 };
            values[i] = s * 0.5;
            values[3] = (component(rows[k], j) - component(rows[j], k)) * inverse_scale;
            values[j] = (component(rows[j], i) + component(rows[i], j)) * inverse_scale;
            values[k] = (component(rows[k], i) + component(rows[i], k)) * inverse_scale;

            return .{ .x = values[0], .y = values[1], .z = values[2], .w = values[3] };
        }

        fn canonical(self: Self) Self {
            const normalized_value = self.normalized();
            return if (normalized_value.w < 0) normalized_value.negate() else normalized_value;
        }

        fn cubicScalar(from: Real, to: Real, pre: Real, post: Real, weight: Real) Real {
            return 0.5 *
                ((from * 2) +
                    (-pre + to) * weight +
                    (2 * pre - 5 * from + 4 * to - post) * (weight * weight) +
                    (-pre + 3 * from - 3 * to + post) * (weight * weight * weight));
        }

        fn cubicInTimeScalar(
            from: Real,
            to: Real,
            pre: Real,
            post: Real,
            weight: Real,
            to_time: Real,
            pre_time: Real,
            post_time: Real,
        ) Real {
            const t = to_time * weight;
            const a1 = lerpScalar(pre, from, if (pre_time == 0) 0 else (t - pre_time) / -pre_time);
            const a2 = lerpScalar(from, to, if (to_time == 0) 0.5 else t / to_time);
            const a3 = lerpScalar(to, post, if (post_time - to_time == 0) 1 else (t - to_time) / (post_time - to_time));
            const b1 = lerpScalar(a1, a2, if (to_time - pre_time == 0) 0 else (t - pre_time) / (to_time - pre_time));
            const b2 = lerpScalar(a2, a3, if (post_time == 0) 1 else t / post_time);
            return lerpScalar(b1, b2, if (to_time == 0) 0.5 else t / to_time);
        }

        fn lerpScalar(from: Real, to: Real, weight: Real) Real {
            return from + (to - from) * weight;
        }

        fn isEqualApproxScalar(a: Real, b: Real) bool {
            if (a == b) return true;
            var tolerance: Real = C.cmp_epsilon * @abs(a);
            if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
            return @abs(a - b) < tolerance;
        }

        fn isEqualApproxScalarTolerance(a: Real, b: Real, tolerance: Real) bool {
            if (a == b) return true;
            return @abs(a - b) < tolerance;
        }
    };
}

pub const single = struct {
    pub const Quaternion = QuaternionOf(f32);
};

pub const double = struct {
    pub const Quaternion = QuaternionOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Quaternion = precision.Quaternion;

test "Quaternion layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Quaternion));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(double.Quaternion));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Quaternion));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Quaternion));
}

test "Quaternion axis-angle and transform" {
    const Q = single.Quaternion;

    const rotation = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    try std.testing.expect(rotation.isNormalized());
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), rotation.getAngle(), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotation.getAxis().z, 0.00001);

    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);

    const inverse_rotation = rotation.inverse();
    try std.testing.expect(inverse_rotation.mul(rotation).isEqualApprox(Q.identity));
}

test "Quaternion interpolation and euler" {
    const Q = single.Quaternion;
    const V = vector.single.Vector3;

    const from = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, 0);
    const to = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi);
    const half = from.slerp(to, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), half.getAngle(), 0.00001);

    const euler = V{ .x = 0.1, .y = 0.2, .z = 0.3 };
    const quat = Q.fromEuler(euler);
    const round_trip = quat.getEuler();
    try std.testing.expectApproxEqAbs(euler.x, round_trip.x, 0.00001);
    try std.testing.expectApproxEqAbs(euler.y, round_trip.y, 0.00001);
    try std.testing.expectApproxEqAbs(euler.z, round_trip.z, 0.00001);

    const cubic = from.sphericalCubicInterpolate(to, from, to, 0.5);
    try std.testing.expect(cubic.isFinite());
    const cubic_time = from.sphericalCubicInterpolateInTime(to, from, to, 0.5, 1, 0, 2);
    try std.testing.expect(cubic_time.isFinite());
}

test "all Quaternion methods compile" {
    const Q = single.Quaternion;
    const a = Q.fromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, 0.5);
    const b = Q.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, 1.0);

    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.log());
    std.mem.doNotOptimizeAway(a.exp());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerpni(b, 0.5));
    std.mem.doNotOptimizeAway(a.sphericalCubicInterpolate(b, a, b, 0.5));
    std.mem.doNotOptimizeAway(a.sphericalCubicInterpolateInTime(b, a, b, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(Q.fromEuler(.{ .x = 0.1, .y = 0.2, .z = 0.3 }));
    std.mem.doNotOptimizeAway(a.getEuler());
    std.mem.doNotOptimizeAway(a.getAxis());
    std.mem.doNotOptimizeAway(a.getAngle());
    std.mem.doNotOptimizeAway(a.add(b));
    std.mem.doNotOptimizeAway(a.sub(b));
    std.mem.doNotOptimizeAway(a.negate());
    std.mem.doNotOptimizeAway(a.scale(2));
    std.mem.doNotOptimizeAway(a.dividedBy(2));
    std.mem.doNotOptimizeAway(a.mul(b));
    std.mem.doNotOptimizeAway(a.xform(.{ .x = 1, .y = 2, .z = 3 }));
    std.mem.doNotOptimizeAway(Q.fromBasisRows(a.toBasisRows()));
}

test "Quaternion double precision" {
    const Q = double.Quaternion;
    const rotation = Q.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotated.y, 1e-12);
}

fn component(value: anytype, index: usize) @TypeOf(value.x) {
    return switch (index) {
        0 => value.x,
        1 => value.y,
        2 => value.z,
        else => unreachable,
    };
}

const std = @import("std");
const bindings = @import("bindings");
const auto = @import("../auto/auto.zig");
const generated_namespace = @import("generated/quaternion.zig");
const vector = @import("vector.zig");
const constants = @import("constants.zig");
