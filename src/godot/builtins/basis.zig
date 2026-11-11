//! Pure-Zig implementation of Godot's `Basis` builtin.
//!
//! Follows `core/math/basis.{h,cpp}`. Quaternion/Euler-dependent methods
//! (`slerp`, `get_rotation_quaternion`, `get_euler`, `from_euler`) are left out
//! until the Quaternion builtin exists. Operators are exposed as named methods
//! (`mul`, `xform`) since Zig does not provide user-defined operator overloading.

pub const EulerOrder = bindings.enums.EulerOrder;

pub fn BasisOf(comptime Real: type) type {
    const V3 = vec.Vector(Real, 3);
    const C = constants.For(Real);

    return extern struct {
        rows: [3]V3 = .{ .zero, .zero, .zero },

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Basis {
            return @as(*const bindings.builtins.Basis, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Basis => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Basis => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Basis => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Basis by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub const identity: Self = .{ .rows = .{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        } };
        pub const flipX: Self = .{ .rows = .{
            .{ .x = -1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        } };
        pub const flipY: Self = .{ .rows = .{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = -1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        } };
        pub const flipZ: Self = .{ .rows = .{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = -1 },
        } };

        pub fn fromRows(row0: V3, row1: V3, row2: V3) Self {
            return .{ .rows = .{ row0, row1, row2 } };
        }

        /// Matches Godot's `Basis(x_axis, y_axis, z_axis)` constructor: the
        /// arguments are columns, not rows.
        pub fn fromColumns(x_axis: V3, y_axis: V3, z_axis: V3) Self {
            return .{ .rows = .{
                .{ .x = x_axis.x, .y = y_axis.x, .z = z_axis.x },
                .{ .x = x_axis.y, .y = y_axis.y, .z = z_axis.y },
                .{ .x = x_axis.z, .y = y_axis.z, .z = z_axis.z },
            } };
        }

        pub fn fromScale(scale: V3) Self {
            return .{ .rows = .{
                .{ .x = scale.x, .y = 0, .z = 0 },
                .{ .x = 0, .y = scale.y, .z = 0 },
                .{ .x = 0, .y = 0, .z = scale.z },
            } };
        }

        /// Rotation matrix from an axis and angle (same convention as
        /// `Basis::set_axis_angle`).
        pub fn fromAxisAngle(axis: V3, angle: Real) Self {
            const cosine = @cos(angle);
            const sine = @sin(angle);
            const t = 1 - cosine;

            const axis_sq_x = axis.x * axis.x;
            const axis_sq_y = axis.y * axis.y;
            const axis_sq_z = axis.z * axis.z;

            const xyzt = axis.x * axis.y * t;
            const zyxs = axis.z * sine;
            const xzyt = axis.x * axis.z * t;
            const yzxs = axis.y * sine;
            const yzzt = axis.y * axis.z * t;
            const xzys = axis.x * sine;

            return .{ .rows = .{
                .{
                    .x = axis_sq_x + cosine * (1 - axis_sq_x),
                    .y = xyzt - zyxs,
                    .z = xzyt + yzxs,
                },
                .{
                    .x = xyzt + zyxs,
                    .y = axis_sq_y + cosine * (1 - axis_sq_y),
                    .z = yzzt - xzys,
                },
                .{
                    .x = xzyt - yzxs,
                    .y = yzzt + xzys,
                    .z = axis_sq_z + cosine * (1 - axis_sq_z),
                },
            } };
        }

        pub fn getColumn(self: Self, index: usize) V3 {
            return switch (index) {
                0 => .{ .x = self.rows[0].x, .y = self.rows[1].x, .z = self.rows[2].x },
                1 => .{ .x = self.rows[0].y, .y = self.rows[1].y, .z = self.rows[2].y },
                2 => .{ .x = self.rows[0].z, .y = self.rows[1].z, .z = self.rows[2].z },
                else => unreachable,
            };
        }

        pub fn setColumn(self: *Self, index: usize, value: V3) void {
            switch (index) {
                0 => {
                    self.rows[0].x = value.x;
                    self.rows[1].x = value.y;
                    self.rows[2].x = value.z;
                },
                1 => {
                    self.rows[0].y = value.x;
                    self.rows[1].y = value.y;
                    self.rows[2].y = value.z;
                },
                2 => {
                    self.rows[0].z = value.x;
                    self.rows[1].z = value.y;
                    self.rows[2].z = value.z;
                },
                else => unreachable,
            }
        }

        pub fn getX(self: Self) V3 {
            return self.getColumn(0);
        }

        pub fn setX(self: *Self, value: V3) void {
            self.setColumn(0, value);
        }

        pub fn getY(self: Self) V3 {
            return self.getColumn(1);
        }

        pub fn setY(self: *Self, value: V3) void {
            self.setColumn(1, value);
        }

        pub fn getZ(self: Self) V3 {
            return self.getColumn(2);
        }

        pub fn setZ(self: *Self, value: V3) void {
            self.setColumn(2, value);
        }

        pub fn transposed(self: Self) Self {
            return .{ .rows = .{
                .{ .x = self.rows[0].x, .y = self.rows[1].x, .z = self.rows[2].x },
                .{ .x = self.rows[0].y, .y = self.rows[1].y, .z = self.rows[2].y },
                .{ .x = self.rows[0].z, .y = self.rows[1].z, .z = self.rows[2].z },
            } };
        }

        pub fn determinant(self: Self) Real {
            return self.rows[0].x * (self.rows[1].y * self.rows[2].z - self.rows[1].z * self.rows[2].y) -
                self.rows[0].y * (self.rows[1].x * self.rows[2].z - self.rows[1].z * self.rows[2].x) +
                self.rows[0].z * (self.rows[1].x * self.rows[2].y - self.rows[1].y * self.rows[2].x);
        }

        pub fn inverse(self: Self) Self {
            const det = self.determinant();
            const inv_det = 1 / det;

            const a = self.rows;
            return .{ .rows = .{
                .{
                    .x = (a[1].y * a[2].z - a[1].z * a[2].y) * inv_det,
                    .y = (a[0].z * a[2].y - a[0].y * a[2].z) * inv_det,
                    .z = (a[0].y * a[1].z - a[0].z * a[1].y) * inv_det,
                },
                .{
                    .x = (a[1].z * a[2].x - a[1].x * a[2].z) * inv_det,
                    .y = (a[0].x * a[2].z - a[0].z * a[2].x) * inv_det,
                    .z = (a[0].z * a[1].x - a[0].x * a[1].z) * inv_det,
                },
                .{
                    .x = (a[1].x * a[2].y - a[1].y * a[2].x) * inv_det,
                    .y = (a[0].y * a[2].x - a[0].x * a[2].y) * inv_det,
                    .z = (a[0].x * a[1].y - a[0].y * a[1].x) * inv_det,
                },
            } };
        }

        pub fn orthonormalized(self: Self) Self {
            var result = self;

            const column_x = result.getColumn(0);
            const x = column_x.normalized();

            const column_y = result.getColumn(1);
            const y = column_y.sub(x.scale(x.dot(column_y))).normalized();

            const column_z = result.getColumn(2);
            const z = column_z
                .sub(x.scale(x.dot(column_z)))
                .sub(y.scale(y.dot(column_z)))
                .normalized();

            result.setColumn(0, x);
            result.setColumn(1, y);
            result.setColumn(2, z);
            return result;
        }

        pub fn xform(self: Self, vector: V3) V3 {
            return .{
                .x = self.rows[0].dot(vector),
                .y = self.rows[1].dot(vector),
                .z = self.rows[2].dot(vector),
            };
        }

        /// Matrix multiplication, `self * other`.
        pub fn mul(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (0..3) |i| {
                inline for (0..3) |j| {
                    var value: Real = 0;
                    inline for (0..3) |k| {
                        value += component(self.rows[i], k) * component(other.rows[k], j);
                    }
                    setComponent(&result.rows[i], j, value);
                }
            }
            return result;
        }

        pub fn scaled(self: Self, scale_value: V3) Self {
            return .{ .rows = .{
                self.rows[0].scale(scale_value.x),
                self.rows[1].scale(scale_value.y),
                self.rows[2].scale(scale_value.z),
            } };
        }

        pub fn scaledLocal(self: Self, scale_value: V3) Self {
            return .{ .rows = .{
                self.rows[0].mul(scale_value),
                self.rows[1].mul(scale_value),
                self.rows[2].mul(scale_value),
            } };
        }

        pub fn rotated(self: Self, axis: V3, angle: Real) Self {
            return fromAxisAngle(axis, angle).mul(self);
        }

        pub fn tdotx(self: Self, vector: V3) Real {
            return self.rows[0].x * vector.x + self.rows[1].x * vector.y + self.rows[2].x * vector.z;
        }

        pub fn tdoty(self: Self, vector: V3) Real {
            return self.rows[0].y * vector.x + self.rows[1].y * vector.y + self.rows[2].y * vector.z;
        }

        pub fn tdotz(self: Self, vector: V3) Real {
            return self.rows[0].z * vector.x + self.rows[1].z * vector.y + self.rows[2].z * vector.z;
        }

        pub fn getScale(self: Self) V3 {
            const scale_abs = V3{
                .x = self.getColumn(0).length(),
                .y = self.getColumn(1).length(),
                .z = self.getColumn(2).length(),
            };
            const det = self.determinant();
            const sign: Real = if (det < 0) -1 else if (det > 0) 1 else 0;
            return scale_abs.scale(sign);
        }

        pub fn fromQuaternion(value: quaternion.QuaternionOf(Real)) Self {
            return .{ .rows = value.toBasisRows() };
        }

        pub fn getEuler(self: Self, order: EulerOrder) V3 {
            const epsilon = C.euler_epsilon;
            return switch (order) {
                .xyz => blk: {
                    const sy = self.rows[0].z;
                    if (sy < (1 - epsilon)) {
                        if (sy > -(1 - epsilon)) {
                            if (self.rows[1].x == 0 and self.rows[0].y == 0 and self.rows[1].z == 0 and self.rows[2].y == 0 and self.rows[1].y == 1) {
                                break :blk V3{ .x = 0, .y = std.math.atan2(sy, self.rows[0].x), .z = 0 };
                            }
                            break :blk V3{
                                .x = std.math.atan2(-self.rows[1].z, self.rows[2].z),
                                .y = std.math.asin(sy),
                                .z = std.math.atan2(-self.rows[0].y, self.rows[0].x),
                            };
                        }
                        break :blk V3{ .x = std.math.atan2(self.rows[2].y, self.rows[1].y), .y = -std.math.pi / 2.0, .z = 0 };
                    }
                    break :blk V3{ .x = std.math.atan2(self.rows[2].y, self.rows[1].y), .y = std.math.pi / 2.0, .z = 0 };
                },
                .xzy => blk: {
                    const sz = self.rows[0].y;
                    if (sz < (1 - epsilon)) {
                        if (sz > -(1 - epsilon)) {
                            break :blk V3{
                                .x = std.math.atan2(self.rows[2].y, self.rows[1].y),
                                .y = std.math.atan2(self.rows[0].z, self.rows[0].x),
                                .z = std.math.asin(-sz),
                            };
                        }
                        break :blk V3{ .x = -std.math.atan2(self.rows[1].z, self.rows[2].z), .y = 0, .z = std.math.pi / 2.0 };
                    }
                    break :blk V3{ .x = -std.math.atan2(self.rows[1].z, self.rows[2].z), .y = 0, .z = -std.math.pi / 2.0 };
                },
                .yxz => blk: {
                    const m12 = self.rows[1].z;
                    if (m12 < (1 - epsilon)) {
                        if (m12 > -(1 - epsilon)) {
                            if (self.rows[1].x == 0 and self.rows[0].y == 0 and self.rows[0].z == 0 and self.rows[2].x == 0 and self.rows[0].x == 1) {
                                break :blk V3{ .x = std.math.atan2(-m12, self.rows[1].y), .y = 0, .z = 0 };
                            }
                            break :blk V3{
                                .x = std.math.asin(-m12),
                                .y = std.math.atan2(self.rows[0].z, self.rows[2].z),
                                .z = std.math.atan2(self.rows[1].x, self.rows[1].y),
                            };
                        }
                        break :blk V3{ .x = std.math.pi / 2.0, .y = std.math.atan2(self.rows[0].y, self.rows[0].x), .z = 0 };
                    }
                    break :blk V3{ .x = -std.math.pi / 2.0, .y = -std.math.atan2(self.rows[0].y, self.rows[0].x), .z = 0 };
                },
                .yzx => blk: {
                    const sz = self.rows[1].x;
                    if (sz < (1 - epsilon)) {
                        if (sz > -(1 - epsilon)) {
                            break :blk V3{
                                .x = std.math.atan2(-self.rows[1].z, self.rows[1].y),
                                .y = std.math.atan2(-self.rows[2].x, self.rows[0].x),
                                .z = std.math.asin(sz),
                            };
                        }
                        break :blk V3{ .x = std.math.atan2(self.rows[2].y, self.rows[2].z), .y = 0, .z = -std.math.pi / 2.0 };
                    }
                    break :blk V3{ .x = std.math.atan2(self.rows[2].y, self.rows[2].z), .y = 0, .z = std.math.pi / 2.0 };
                },
                .zxy => blk: {
                    const sx = self.rows[2].y;
                    if (sx < (1 - epsilon)) {
                        if (sx > -(1 - epsilon)) {
                            break :blk V3{
                                .x = std.math.asin(sx),
                                .y = std.math.atan2(-self.rows[2].x, self.rows[2].z),
                                .z = std.math.atan2(-self.rows[0].y, self.rows[1].y),
                            };
                        }
                        break :blk V3{ .x = -std.math.pi / 2.0, .y = std.math.atan2(self.rows[0].z, self.rows[0].x), .z = 0 };
                    }
                    break :blk V3{ .x = std.math.pi / 2.0, .y = std.math.atan2(self.rows[0].z, self.rows[0].x), .z = 0 };
                },
                .zyx => blk: {
                    const sy = self.rows[2].x;
                    if (sy < (1 - epsilon)) {
                        if (sy > -(1 - epsilon)) {
                            break :blk V3{
                                .x = std.math.atan2(self.rows[2].y, self.rows[2].z),
                                .y = std.math.asin(-sy),
                                .z = std.math.atan2(self.rows[1].x, self.rows[0].x),
                            };
                        }
                        break :blk V3{ .x = 0, .y = std.math.pi / 2.0, .z = -std.math.atan2(self.rows[0].y, self.rows[1].y) };
                    }
                    break :blk V3{ .x = 0, .y = -std.math.pi / 2.0, .z = -std.math.atan2(self.rows[0].y, self.rows[1].y) };
                },
            };
        }

        pub fn fromEuler(euler: V3, order: EulerOrder) Self {
            const cx = @cos(euler.x);
            const sx = @sin(euler.x);
            const cy = @cos(euler.y);
            const sy = @sin(euler.y);
            const cz = @cos(euler.z);
            const sz = @sin(euler.z);

            const xmat = Self{ .rows = .{
                .{ .x = 1, .y = 0, .z = 0 },
                .{ .x = 0, .y = cx, .z = -sx },
                .{ .x = 0, .y = sx, .z = cx },
            } };
            const ymat = Self{ .rows = .{
                .{ .x = cy, .y = 0, .z = sy },
                .{ .x = 0, .y = 1, .z = 0 },
                .{ .x = -sy, .y = 0, .z = cy },
            } };
            const zmat = Self{ .rows = .{
                .{ .x = cz, .y = -sz, .z = 0 },
                .{ .x = sz, .y = cz, .z = 0 },
                .{ .x = 0, .y = 0, .z = 1 },
            } };

            return switch (order) {
                .xyz => xmat.mul(ymat.mul(zmat)),
                .xzy => xmat.mul(zmat).mul(ymat),
                .yxz => ymat.mul(xmat).mul(zmat),
                .yzx => ymat.mul(zmat).mul(xmat),
                .zxy => zmat.mul(xmat).mul(ymat),
                .zyx => zmat.mul(ymat).mul(xmat),
            };
        }

        pub fn getRotationQuaternion(self: Self) quaternion.QuaternionOf(Real) {
            var matrix = self.orthonormalized();
            if (matrix.determinant() < 0) {
                matrix = matrix.scaled(V3{ .x = -1, .y = -1, .z = -1 });
            }
            return quaternion.QuaternionOf(Real).fromBasisRows(matrix.rows);
        }

        pub fn slerp(self: Self, to: Self, weight: Real) Self {
            const Q = quaternion.QuaternionOf(Real);
            const from_quaternion = Q.fromBasisRows(self.rows).normalized();
            const to_quaternion = Q.fromBasisRows(to.rows).normalized();
            var result = fromQuaternion(from_quaternion.slerp(to_quaternion, weight));

            result.rows[0] = result.rows[0].scale(lerpScalar(self.rows[0].length(), to.rows[0].length(), weight));
            result.rows[1] = result.rows[1].scale(lerpScalar(self.rows[1].length(), to.rows[1].length(), weight));
            result.rows[2] = result.rows[2].scale(lerpScalar(self.rows[2].length(), to.rows[2].length(), weight));
            return result;
        }

        pub fn isOrthonormal(self: Self) bool {
            const x = self.getColumn(0);
            const y = self.getColumn(1);
            const z = self.getColumn(2);
            return isEqualApproxScalar(x.lengthSquared(), 1) and
                isEqualApproxScalar(y.lengthSquared(), 1) and
                isEqualApproxScalar(z.lengthSquared(), 1) and
                isZeroApproxScalar(x.dot(y)) and
                isZeroApproxScalar(x.dot(z)) and
                isZeroApproxScalar(y.dot(z));
        }

        pub fn isConformal(self: Self) bool {
            const x = self.getColumn(0);
            const y = self.getColumn(1);
            const z = self.getColumn(2);
            const x_len_sq = x.lengthSquared();
            return isEqualApproxScalar(x_len_sq, y.lengthSquared()) and
                isEqualApproxScalar(x_len_sq, z.lengthSquared()) and
                isZeroApproxScalar(x.dot(y)) and
                isZeroApproxScalar(x.dot(z)) and
                isZeroApproxScalar(y.dot(z));
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.rows[0].isEqualApprox(other.rows[0]) and
                self.rows[1].isEqualApprox(other.rows[1]) and
                self.rows[2].isEqualApprox(other.rows[2]);
        }

        pub fn isFinite(self: Self) bool {
            return self.rows[0].isFinite() and self.rows[1].isFinite() and self.rows[2].isFinite();
        }

        pub fn lookingAt(target: V3, up: V3, use_model_front: bool) Self {
            var v_z = target.normalized();
            if (!use_model_front) v_z = v_z.negate();

            var v_x = up.cross(v_z);
            if (v_x.isZeroApprox()) v_x = anyPerpendicular(up);
            v_x = v_x.normalized();

            const v_y = v_z.cross(v_x);
            return fromColumns(v_x, v_y, v_z);
        }

        fn anyPerpendicular(vector: V3) V3 {
            const abs_x = @abs(vector.x);
            const abs_y = @abs(vector.y);
            const abs_z = @abs(vector.z);
            const axis = if (abs_x <= abs_y and abs_x <= abs_z) V3.right else V3.up;
            return vector.cross(axis).normalized();
        }

        fn isEqualApproxScalar(a: Real, b: Real) bool {
            if (a == b) return true;
            var tolerance: Real = C.cmp_epsilon * @abs(a);
            if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
            return @abs(a - b) < tolerance;
        }

        fn isZeroApproxScalar(value: Real) bool {
            return @abs(value) < C.cmp_epsilon;
        }

        fn lerpScalar(from: Real, to: Real, weight: Real) Real {
            return from + (to - from) * weight;
        }
    };
}

pub const single = struct {
    pub const Basis = BasisOf(f32);
};

pub const double = struct {
    pub const Basis = BasisOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Basis = precision.Basis;

test "Basis column members" {
    const B = single.Basis;
    var basis = B.identity;
    basis.setX(.{ .x = 1, .y = 2, .z = 3 });
    basis.setY(.{ .x = 4, .y = 5, .z = 6 });
    basis.setZ(.{ .x = 7, .y = 8, .z = 9 });
    try std.testing.expectEqual(vec.single.Vector3{ .x = 1, .y = 2, .z = 3 }, basis.getX());
    try std.testing.expectEqual(vec.single.Vector3{ .x = 4, .y = 5, .z = 6 }, basis.getY());
    try std.testing.expectEqual(vec.single.Vector3{ .x = 7, .y = 8, .z = 9 }, basis.getZ());
}

test "Basis layout" {
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(single.Basis));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(double.Basis));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Basis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Basis));
}

test "Basis identity and transformations" {
    const B = single.Basis;
    const V = vec.single.Vector3;

    const identity = B.identity;
    try std.testing.expect(identity.isOrthonormal());
    try std.testing.expectEqual(V{ .x = 1, .y = 2, .z = 3 }, identity.xform(.{ .x = 1, .y = 2, .z = 3 }));

    const scale = B.fromScale(.{ .x = 2, .y = 3, .z = 4 });
    try std.testing.expectEqual(@as(f32, 24), scale.determinant());
    try std.testing.expectEqual(V{ .x = 2, .y = 6, .z = 12 }, scale.xform(.{ .x = 1, .y = 2, .z = 3 }));
    try std.testing.expectEqual(V{ .x = 2, .y = 3, .z = 4 }, scale.getScale());

    const inverse = scale.inverse();
    try std.testing.expect(inverse.mul(scale).isEqualApprox(identity));

    const transposed = scale.transposed();
    try std.testing.expectEqual(V{ .x = 2, .y = 0, .z = 0 }, transposed.getColumn(0));

    const rotation = B.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    const rotated = rotation.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);
    try std.testing.expect(rotation.isOrthonormal());
    try std.testing.expect(rotation.isConformal());
    try std.testing.expectEqual(@as(f32, 1), rotation.determinant());
}

test "Basis quaternion and slerp" {
    const B = single.Basis;

    const rotation = B.fromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 4.0);
    const quaternion_value = rotation.getRotationQuaternion();
    try std.testing.expect(quaternion_value.isNormalized());

    const round_trip = B.fromQuaternion(quaternion_value);
    try std.testing.expect(round_trip.isEqualApprox(rotation));

    const slerped = B.identity.slerp(rotation, 0.5);
    const transformed = slerped.xform(.{ .x = 1, .y = 0, .z = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.9238795), transformed.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3826834), transformed.y, 0.0001);
}

test "Basis Euler orders round-trip" {
    const B = single.Basis;
    const euler = vec.single.Vector3{ .x = 0.1, .y = 0.2, .z = 0.3 };

    for ([_]EulerOrder{ .xyz, .xzy, .yxz, .yzx, .zxy, .zyx }) |order| {
        const rotation = B.fromEuler(euler, order);
        const round_trip = rotation.getEuler(order);
        try std.testing.expectApproxEqAbs(euler.x, round_trip.x, 0.00001);
        try std.testing.expectApproxEqAbs(euler.y, round_trip.y, 0.00001);
        try std.testing.expectApproxEqAbs(euler.z, round_trip.z, 0.00001);
    }
}

test "Basis orthonormalized and lookingAt" {
    const B = single.Basis;

    const skew = B.fromRows(
        .{ .x = 1, .y = 2, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 2 },
    );
    try std.testing.expect(!skew.isOrthonormal());
    try std.testing.expect(skew.orthonormalized().isOrthonormal());

    const look = B.lookingAt(.{ .x = 1, .y = 0, .z = 0 }, .{ .x = 0, .y = 1, .z = 0 }, false);
    try std.testing.expectEqual(vec.single.Vector3{ .x = 0, .y = 1, .z = 0 }, look.getColumn(1));

    const double_look = double.Basis.lookingAt(
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        false,
    );
    try std.testing.expect(double_look.isOrthonormal());
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
const vec = @import("vector.zig");
const quaternion = @import("quaternion.zig");
const constants = @import("constants.zig");
