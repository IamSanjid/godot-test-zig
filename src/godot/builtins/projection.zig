//! Pure-Zig implementation of Godot's `Projection` builtin.
//!
//! Follows `core/math/projection.{h,cpp}`. `create_light_atlas_rect` is deferred
//! until the `Rect2` builtin exists. Operators are exposed as named methods
//! (`mul`, `xform`) since Zig does not provide user-defined operator symbols.

pub fn ProjectionOf(comptime Real: type) type {
    const V2 = vector.Vector(Real, 2);
    const V3 = vector.Vector(Real, 3);
    const V4 = vector.Vector(Real, 4);
    const AABB = aabb.AabbOf(Real);
    const Plane = plane.PlaneOf(Real);

    return extern struct {
        pub const GodotClassName = "Projection";

        columns: [4]V4 = .{
            .{ .x = 1, .y = 0, .z = 0, .w = 0 },
            .{ .x = 0, .y = 1, .z = 0, .w = 0 },
            .{ .x = 0, .y = 0, .z = 1, .w = 0 },
            .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        },

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Projection {
            return @as(*const bindings.builtins.Projection, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Projection => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Projection => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Projection => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Projection by value or a pointer to it, found: " ++ @typeName(V)),
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

        pub const Planes = enum(u3) {
            near,
            far,
            left,
            top,
            right,
            bottom,
        };

        pub const identity: Self = .{};
        pub const zero: Self = .{ .columns = .{ .zero, .zero, .zero, .zero } };

        pub fn getX(self: Self) V4 {
            return self.columns[0];
        }

        pub fn setX(self: *Self, value: V4) void {
            self.columns[0] = value;
        }

        pub fn getY(self: Self) V4 {
            return self.columns[1];
        }

        pub fn setY(self: *Self, value: V4) void {
            self.columns[1] = value;
        }

        pub fn getZ(self: Self) V4 {
            return self.columns[2];
        }

        pub fn setZ(self: *Self, value: V4) void {
            self.columns[2] = value;
        }

        pub fn getW(self: Self) V4 {
            return self.columns[3];
        }

        pub fn setW(self: *Self, value: V4) void {
            self.columns[3] = value;
        }

        pub fn determinant(self: Self) Real {
            var matrix: [4][4]Real = undefined;
            for (0..4) |row| {
                for (0..4) |column| {
                    matrix[row][column] = component4(self.columns[column], row);
                }
            }

            var det: Real = 1;
            for (0..4) |i| {
                var pivot = i;
                for (i + 1..4) |row| {
                    if (@abs(matrix[row][i]) > @abs(matrix[pivot][i])) pivot = row;
                }
                if (matrix[pivot][i] == 0) return 0;

                if (pivot != i) {
                    const tmp = matrix[pivot];
                    matrix[pivot] = matrix[i];
                    matrix[i] = tmp;
                    det = -det;
                }

                det *= matrix[i][i];
                for (i + 1..4) |row| {
                    const factor = matrix[row][i] / matrix[i][i];
                    for (i..4) |column| {
                        matrix[row][column] -= factor * matrix[i][column];
                    }
                }
            }
            return det;
        }

        pub fn inverse(self: Self) Self {
            var augmented: [4][8]Real = undefined;
            for (0..4) |row| {
                for (0..4) |column| {
                    augmented[row][column] = component4(self.columns[column], row);
                    augmented[row][column + 4] = if (row == column) 1 else 0;
                }
            }

            for (0..4) |i| {
                var pivot = i;
                for (i + 1..4) |row| {
                    if (@abs(augmented[row][i]) > @abs(augmented[pivot][i])) pivot = row;
                }
                if (augmented[pivot][i] == 0) return identity;

                if (pivot != i) {
                    const tmp = augmented[pivot];
                    augmented[pivot] = augmented[i];
                    augmented[i] = tmp;
                }

                const divisor = augmented[i][i];
                for (0..8) |column| augmented[i][column] /= divisor;

                for (0..4) |row| {
                    if (row == i) continue;
                    const factor = augmented[row][i];
                    for (0..8) |column| {
                        augmented[row][column] -= factor * augmented[i][column];
                    }
                }
            }

            var result: Self = undefined;
            for (0..4) |column| {
                result.columns[column] = .{
                    .x = augmented[0][column + 4],
                    .y = augmented[1][column + 4],
                    .z = augmented[2][column + 4],
                    .w = augmented[3][column + 4],
                };
            }
            return result;
        }

        pub fn mul(self: Self, other: Self) Self {
            var result: Self = undefined;
            for (0..4) |column| {
                for (0..4) |row| {
                    var value: Real = 0;
                    for (0..4) |k| {
                        value += component4(self.columns[k], row) * component4(other.columns[column], k);
                    }
                    setComponent4(&result.columns[column], row, value);
                }
            }
            return result;
        }

        pub fn xform(self: Self, vector_value: V4) V4 {
            return .{
                .x = self.columns[0].x * vector_value.x + self.columns[1].x * vector_value.y + self.columns[2].x * vector_value.z + self.columns[3].x * vector_value.w,
                .y = self.columns[0].y * vector_value.x + self.columns[1].y * vector_value.y + self.columns[2].y * vector_value.z + self.columns[3].y * vector_value.w,
                .z = self.columns[0].z * vector_value.x + self.columns[1].z * vector_value.y + self.columns[2].z * vector_value.z + self.columns[3].z * vector_value.w,
                .w = self.columns[0].w * vector_value.x + self.columns[1].w * vector_value.y + self.columns[2].w * vector_value.z + self.columns[3].w * vector_value.w,
            };
        }

        pub fn xformInv(self: Self, vector_value: V4) V4 {
            return .{
                .x = self.columns[0].x * vector_value.x + self.columns[0].y * vector_value.y + self.columns[0].z * vector_value.z + self.columns[0].w * vector_value.w,
                .y = self.columns[1].x * vector_value.x + self.columns[1].y * vector_value.y + self.columns[1].z * vector_value.z + self.columns[1].w * vector_value.w,
                .z = self.columns[2].x * vector_value.x + self.columns[2].y * vector_value.y + self.columns[2].z * vector_value.z + self.columns[2].w * vector_value.w,
                .w = self.columns[3].x * vector_value.x + self.columns[3].y * vector_value.y + self.columns[3].z * vector_value.z + self.columns[3].w * vector_value.w,
            };
        }

        /// The `Projection * Vector3` operator (perspective divide).
        pub fn xformVector3(self: Self, vector_value: V3) V3 {
            var result = V3{
                .x = self.columns[0].x * vector_value.x + self.columns[1].x * vector_value.y + self.columns[2].x * vector_value.z + self.columns[3].x,
                .y = self.columns[0].y * vector_value.x + self.columns[1].y * vector_value.y + self.columns[2].y * vector_value.z + self.columns[3].y,
                .z = self.columns[0].z * vector_value.x + self.columns[1].z * vector_value.y + self.columns[2].z * vector_value.z + self.columns[3].z,
            };
            const w = self.columns[0].w * vector_value.x + self.columns[1].w * vector_value.y + self.columns[2].w * vector_value.z + self.columns[3].w;
            result = result.scale(1 / w);
            return result;
        }

        pub fn xformPlane(self: Self, plane_value: Plane) Plane {
            return .{
                .normal = .{
                    .x = self.columns[0].x * plane_value.normal.x + self.columns[1].x * plane_value.normal.y + self.columns[2].x * plane_value.normal.z + self.columns[3].x * plane_value.d,
                    .y = self.columns[0].y * plane_value.normal.x + self.columns[1].y * plane_value.normal.y + self.columns[2].y * plane_value.normal.z + self.columns[3].y * plane_value.d,
                    .z = self.columns[0].z * plane_value.normal.x + self.columns[1].z * plane_value.normal.y + self.columns[2].z * plane_value.normal.z + self.columns[3].z * plane_value.d,
                },
                .d = self.columns[0].w * plane_value.normal.x + self.columns[1].w * plane_value.normal.y + self.columns[2].w * plane_value.normal.z + self.columns[3].w * plane_value.d,
            };
        }

        pub fn createDepthCorrection(flip_y: bool) Self {
            var result = Self.identity;
            result.columns[1].y = if (flip_y) -1 else 1;
            result.columns[2].z = -0.5;
            result.columns[3].z = 0.5;
            return result;
        }

        pub fn createPerspective(
            fovy_degrees: Real,
            aspect: Real,
            z_near: Real,
            z_far: Real,
            flip_fov: bool,
        ) Self {
            var fovy = fovy_degrees;
            if (flip_fov) fovy = getFovy(fovy, 1 / aspect);

            const radians = std.math.degreesToRadians(fovy / 2);
            const delta_z = z_far - z_near;
            const sine = @sin(radians);
            if (delta_z == 0 or sine == 0 or aspect == 0) return identity;

            const cotangent = @cos(radians) / sine;
            var result = Self.identity;
            result.columns[0].x = cotangent / aspect;
            result.columns[1].y = cotangent;
            result.columns[2].z = -(z_far + z_near) / delta_z;
            result.columns[2].w = -1;
            result.columns[3].z = -2 * z_near * z_far / delta_z;
            result.columns[3].w = 0;
            return result;
        }

        pub fn createPerspectiveHmd(
            fovy_degrees: Real,
            aspect: Real,
            z_near: Real,
            z_far: Real,
            flip_fov: bool,
            eye: i32,
            intraocular_dist: Real,
            convergence_dist: Real,
        ) Self {
            var fovy = fovy_degrees;
            if (flip_fov) fovy = getFovy(fovy, 1 / aspect);

            const ymax = z_near * @tan(std.math.degreesToRadians(fovy / 2));
            const xmax = ymax * aspect;
            const frustum_shift = (intraocular_dist / 2) * z_near / convergence_dist;

            var left: Real = undefined;
            var right: Real = undefined;
            var model_translation: Real = undefined;
            switch (eye) {
                1 => {
                    left = -xmax + frustum_shift;
                    right = xmax + frustum_shift;
                    model_translation = intraocular_dist / 2;
                },
                2 => {
                    left = -xmax - frustum_shift;
                    right = xmax - frustum_shift;
                    model_translation = -intraocular_dist / 2;
                },
                else => {
                    left = -xmax;
                    right = xmax;
                    model_translation = 0;
                },
            }

            var result = createFrustum(left, right, -ymax, ymax, z_near, z_far);
            var translation = Self.identity;
            translation.columns[3].x = model_translation;
            result = result.mul(translation);
            return result;
        }

        pub fn createLightAtlasRect(rect_value: rect.Rect2Of(Real)) Self {
            var result = Self.identity;
            result.columns[0].x = rect_value.size.x;
            result.columns[1].y = rect_value.size.y;
            result.columns[2].z = 1;
            result.columns[3].x = rect_value.position.x;
            result.columns[3].y = rect_value.position.y;
            result.columns[3].w = 1;
            return result;
        }

        pub fn createForHmd(
            eye: i32,
            aspect: Real,
            intraocular_dist: Real,
            display_width: Real,
            display_to_lens: Real,
            oversample: Real,
            z_near: Real,
            z_far: Real,
        ) Self {
            var f1 = (intraocular_dist * 0.5) / display_to_lens;
            var f2 = ((display_width - intraocular_dist) * 0.5) / display_to_lens;
            var f3 = (display_width / 4) / display_to_lens;

            const add = ((f1 + f2) * (oversample - 1)) / 2;
            f1 += add;
            f2 += add;
            f3 *= oversample;
            f3 /= aspect;

            return switch (eye) {
                1 => createFrustum(-f2 * z_near, f1 * z_near, -f3 * z_near, f3 * z_near, z_near, z_far),
                2 => createFrustum(-f1 * z_near, f2 * z_near, -f3 * z_near, f3 * z_near, z_near, z_far),
                else => identity,
            };
        }

        pub fn createOrthogonal(
            left: Real,
            right: Real,
            bottom: Real,
            top: Real,
            z_near: Real,
            z_far: Real,
        ) Self {
            var result = Self.identity;
            result.columns[0].x = 2 / (right - left);
            result.columns[3].x = -((right + left) / (right - left));
            result.columns[1].y = 2 / (top - bottom);
            result.columns[3].y = -((top + bottom) / (top - bottom));
            result.columns[2].z = -2 / (z_far - z_near);
            result.columns[3].z = -((z_far + z_near) / (z_far - z_near));
            result.columns[3].w = 1;
            return result;
        }

        pub fn createOrthogonalAspect(
            size: Real,
            aspect: Real,
            z_near: Real,
            z_far: Real,
            flip_fov: bool,
        ) Self {
            const adjusted = if (flip_fov) size else size * aspect;
            return createOrthogonal(
                -adjusted / 2,
                adjusted / 2,
                -adjusted / aspect / 2,
                adjusted / aspect / 2,
                z_near,
                z_far,
            );
        }

        pub fn createFrustum(
            left: Real,
            right: Real,
            bottom: Real,
            top: Real,
            z_near: Real,
            z_far: Real,
        ) Self {
            if (right <= left or top <= bottom or z_far <= z_near) return identity;

            const x = 2 * z_near / (right - left);
            const y = 2 * z_near / (top - bottom);
            const a = (right + left) / (right - left);
            const b = (top + bottom) / (top - bottom);
            const c = -(z_far + z_near) / (z_far - z_near);
            const d = -2 * z_far * z_near / (z_far - z_near);

            var result = Self.zero;
            result.columns[0].x = x;
            result.columns[1].y = y;
            result.columns[2].x = a;
            result.columns[2].y = b;
            result.columns[2].z = c;
            result.columns[2].w = -1;
            result.columns[3].z = d;
            return result;
        }

        pub fn createFrustumAspect(
            size: Real,
            aspect: Real,
            offset: V2,
            z_near: Real,
            z_far: Real,
            flip_fov: bool,
        ) Self {
            const adjusted = if (flip_fov) size else size * aspect;
            return createFrustum(
                -adjusted / 2 + offset.x,
                adjusted / 2 + offset.x,
                -adjusted / aspect / 2 + offset.y,
                adjusted / aspect / 2 + offset.y,
                z_near,
                z_far,
            );
        }

        pub fn createFitAabb(box: AABB) Self {
            const min = box.position;
            const max = box.position.add(box.size);

            var result = Self.identity;
            result.columns[0].x = 2 / (max.x - min.x);
            result.columns[3].x = -(max.x + min.x) / (max.x - min.x);
            result.columns[1].y = 2 / (max.y - min.y);
            result.columns[3].y = -(max.y + min.y) / (max.y - min.y);
            result.columns[2].z = 2 / (max.z - min.z);
            result.columns[3].z = -(max.z + min.z) / (max.z - min.z);
            return result;
        }

        pub fn getFovy(fovx: Real, aspect: Real) Real {
            return std.math.radiansToDegrees(std.math.atan(aspect * @tan(std.math.degreesToRadians(fovx) * 0.5)) * 2);
        }

        pub fn perspectiveZnearAdjusted(self: Self, new_z_near: Real) Self {
            const z_far = self.getZFar();
            const delta_z = z_far - new_z_near;
            var result = self;
            result.columns[2].z = -(z_far + new_z_near) / delta_z;
            result.columns[3].z = -2 * new_z_near * z_far / delta_z;
            return result;
        }

        pub fn getProjectionPlane(self: Self, plane_index: Planes) Plane {
            var result = switch (plane_index) {
                .near => Plane.init(
                    .{
                        .x = self.columns[0].w + self.columns[0].z,
                        .y = self.columns[1].w + self.columns[1].z,
                        .z = self.columns[2].w + self.columns[2].z,
                    },
                    self.columns[3].w + self.columns[3].z,
                ),
                .far => Plane.init(
                    .{
                        .x = self.columns[0].w - self.columns[0].z,
                        .y = self.columns[1].w - self.columns[1].z,
                        .z = self.columns[2].w - self.columns[2].z,
                    },
                    self.columns[3].w - self.columns[3].z,
                ),
                .left => Plane.init(
                    .{
                        .x = self.columns[0].w + self.columns[0].x,
                        .y = self.columns[1].w + self.columns[1].x,
                        .z = self.columns[2].w + self.columns[2].x,
                    },
                    self.columns[3].w + self.columns[3].x,
                ),
                .top => Plane.init(
                    .{
                        .x = self.columns[0].w - self.columns[0].y,
                        .y = self.columns[1].w - self.columns[1].y,
                        .z = self.columns[2].w - self.columns[2].y,
                    },
                    self.columns[3].w - self.columns[3].y,
                ),
                .right => Plane.init(
                    .{
                        .x = self.columns[0].w - self.columns[0].x,
                        .y = self.columns[1].w - self.columns[1].x,
                        .z = self.columns[2].w - self.columns[2].x,
                    },
                    self.columns[3].w - self.columns[3].x,
                ),
                .bottom => Plane.init(
                    .{
                        .x = self.columns[0].w + self.columns[0].y,
                        .y = self.columns[1].w + self.columns[1].y,
                        .z = self.columns[2].w + self.columns[2].y,
                    },
                    self.columns[3].w + self.columns[3].y,
                ),
            };
            result.normal = result.normal.negate().normalized();
            return result;
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            inline for (0..4) |i| {
                if (!self.columns[i].isEqualApprox(other.columns[i])) return false;
            }
            return true;
        }

        pub fn flippedY(self: Self) Self {
            var result = self;
            result.columns[1] = result.columns[1].negate();
            return result;
        }

        pub fn jitterOffseted(self: Self, offset: V2) Self {
            var result = self;
            result.columns[3].x += offset.x;
            result.columns[3].y += offset.y;
            return result;
        }

        pub fn getZFar(self: Self) Real {
            return (self.columns[3].w - self.columns[3].z) / (self.columns[2].w - self.columns[2].z);
        }

        pub fn getZNear(self: Self) Real {
            return (self.columns[3].w + self.columns[3].z) / (self.columns[2].w + self.columns[2].z);
        }

        pub fn getAspect(self: Self) Real {
            return self.columns[1].y / self.columns[0].x;
        }

        pub fn getFov(self: Self) Real {
            if (self.columns[2].x == 0) {
                return std.math.radiansToDegrees(2 * std.math.atan2(1, self.columns[0].x));
            }
            const right = std.math.atan2(self.columns[2].x + 1, self.columns[0].x);
            const left = std.math.atan2(self.columns[2].x - 1, self.columns[0].x);
            return std.math.radiansToDegrees(right - left);
        }

        pub fn isOrthogonal(self: Self) bool {
            return self.columns[2].w == 0;
        }

        pub fn getViewportHalfExtents(self: Self) V2 {
            const w = -self.getZNear() * self.columns[2].w + self.columns[3].w;
            return .{ .x = w / self.columns[0].x, .y = w / self.columns[1].y };
        }

        pub fn getFarPlaneHalfExtents(self: Self) V2 {
            const w = -self.getZFar() * self.columns[2].w + self.columns[3].w;
            return .{ .x = w / self.columns[0].x, .y = w / self.columns[1].y };
        }

        pub fn getPixelsPerMeter(self: Self, for_pixel_width: i32) i32 {
            const width = 2 * (-self.getZNear() * self.columns[2].w + self.columns[3].w) / self.columns[0].x;
            return @intFromFloat(@as(Real, @floatFromInt(for_pixel_width)) / width);
        }

        pub fn getLodMultiplier(self: Self) Real {
            return 2 / self.columns[0].x;
        }
    };
}

fn component4(value: anytype, index: usize) @TypeOf(value.x) {
    return switch (index) {
        0 => value.x,
        1 => value.y,
        2 => value.z,
        3 => value.w,
        else => unreachable,
    };
}

fn setComponent4(value: anytype, index: usize, new_value: @TypeOf(value.x)) void {
    switch (index) {
        0 => value.x = new_value,
        1 => value.y = new_value,
        2 => value.z = new_value,
        3 => value.w = new_value,
        else => unreachable,
    }
}

pub const single = struct {
    pub const Projection = ProjectionOf(f32);
};

pub const double = struct {
    pub const Projection = ProjectionOf(f64);
};

const precision = if (bindings.is_double_precision) double else single;
pub const Projection = precision.Projection;

test "Projection member aliases" {
    const P = single.Projection;
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
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(single.Projection));
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(double.Projection));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Projection));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Projection));
}

test "Projection perspective and inverse" {
    const P = single.Projection;
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
    const P = single.Projection;
    const Box = aabb.single.AABB;

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
    const P = single.Projection;

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
    const P = single.Projection;
    const Box = aabb.single.AABB;
    const Plane = plane.single.Plane;

    const perspective = P.createPerspective(60, 1.5, 0.1, 100, false);
    const hmd = P.createPerspectiveHmd(60, 1.5, 0.1, 100, false, 1, 0.06, 2);
    const for_hmd = P.createForHmd(1, 1.5, 0.06, 0.1, 0.05, 1.2, 0.1, 100);
    const atlas = P.createLightAtlasRect(rect.single.Rect2.init(.{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 }));
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
    const P = double.Projection;
    const perspective = P.createPerspective(60, 1, 0.1, 100, false);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), perspective.getZNear(), 1e-9);
}

const std = @import("std");
const bindings = @import("bindings");
const auto = @import("../auto/auto.zig");
const generated_namespace = @import("generated/projection.zig");
const vector = @import("vector.zig");
const aabb = @import("aabb.zig");
const plane = @import("plane.zig");
const rect = @import("rect.zig");
