//! Pure-Zig implementations of Godot's Vector types.
//!
//! The generated extension interface can construct these through engine calls,
//! but all of the math below is implemented locally, following Godot's
//! `core/math/vector*.h/.cpp` semantics. The types are laid out exactly like
//! their engine counterparts (`extern struct`), so they can cross the
//! GDExtension ABI without conversion on the float types.
//!
//! Method names are Zig-style camelCase versions of the `extension_api.json`
//! names. Constants that would collide with method names (`MIN`/`MAX` vs
//! `min`/`max`) are spelled `minValue`/`maxValue`.

pub fn Vector(comptime T: type, comptime dimension: comptime_int) type {
    if (dimension < 2 or dimension > 4) {
        @compileError("Only 2 to 4 dimensions are supported");
    }

    const info = @typeInfo(T);
    if (info != .float and info != .int) {
        @compileError("Expected either a float or an integer type, found: " ++ @typeName(T));
    }

    return GenericVector(T, dimension, info == .float);
}

fn GenericVector(comptime T: type, comptime dimension: comptime_int, comptime t_is_float: bool) type {
    const Vec = @Vector(dimension, T);

    return switch (dimension) {
        2 => extern struct {
            x: T,
            y: T,

            const Self = @This();
            const H = Helpers(Self);

            pub const Base = T;
            pub const is_float = t_is_float;
            pub const dimensions = dimension;
            pub const VecType = Vec;

            pub fn asVector(self: Self) Vec {
                return .{ self.x, self.y };
            }

            pub fn fromVector(value: Vec) Self {
                return .{ .x = value[0], .y = value[1] };
            }

            pub const zero: Self = .fromVector(@splat(0));
            pub const one: Self = .fromVector(@splat(1));
            pub const inf: Self = if (is_float)
                .fromVector(@splat(std.math.inf(T)))
            else
                @compileError("Vector.inf is only available for float vectors");
            pub const minValue: Self = if (!is_float)
                .fromVector(@splat(std.math.minInt(T)))
            else
                @compileError("Vector.minValue is only available for integer vectors");
            pub const maxValue: Self = if (!is_float)
                .fromVector(@splat(std.math.maxInt(T)))
            else
                @compileError("Vector.maxValue is only available for integer vectors");

            pub const left: Self = .{ .x = -1, .y = 0 };
            pub const right: Self = .{ .x = 1, .y = 0 };
            pub const up: Self = .{ .x = 0, .y = -1 };
            pub const down: Self = .{ .x = 0, .y = 1 };

            pub const add = H.add;
            pub const sub = H.sub;
            pub const mul = H.mul;
            pub const div = H.div;
            pub const scale = H.scale;
            pub const negate = H.negate;
            pub const abs = H.abs;
            pub const sign = H.sign;
            pub const min = H.min;
            pub const max = H.max;
            pub const clamp = H.clamp;
            pub const snapped = H.snapped;
            pub const minAxisIndex = H.minAxisIndex;
            pub const maxAxisIndex = H.maxAxisIndex;
            pub const length = H.length;
            pub const lengthSquared = H.lengthSquared;
            pub const distanceTo = H.distanceTo;
            pub const distanceSquaredTo = H.distanceSquaredTo;
            pub const aspect = H.aspect;

            pub const minf = if (is_float) H.minf else @compileError("Vector.minf requires a float vector");
            pub const maxf = if (is_float) H.maxf else @compileError("Vector.maxf requires a float vector");
            pub const clampf = if (is_float) H.clampf else @compileError("Vector.clampf requires a float vector");
            pub const snappedf = if (is_float) H.snappedf else @compileError("Vector.snappedf requires a float vector");

            pub const mini = if (!is_float) H.mini else @compileError("Vector.mini requires an integer vector");
            pub const maxi = if (!is_float) H.maxi else @compileError("Vector.maxi requires an integer vector");
            pub const clampi = if (!is_float) H.clampi else @compileError("Vector.clampi requires an integer vector");
            pub const snappedi = if (!is_float) H.snappedi else @compileError("Vector.snappedi requires an integer vector");

            pub const angle = if (is_float) H.angle2 else @compileError("Vector.angle requires a float vector");
            pub const angleTo = if (is_float) H.angleTo2 else @compileError("Vector.angleTo requires a float vector");
            pub const angleToPoint = if (is_float) H.angleToPoint2 else @compileError("Vector.angleToPoint requires a float vector");
            pub const directionTo = if (is_float) H.directionTo else @compileError("Vector.directionTo requires a float vector");
            pub const limitLength = if (is_float) H.limitLength else @compileError("Vector.limitLength requires a float vector");
            pub const normalized = if (is_float) H.normalized else @compileError("Vector.normalized requires a float vector");
            pub const isNormalized = if (is_float) H.isNormalized else @compileError("Vector.isNormalized requires a float vector");
            pub const isEqualApprox = if (is_float) H.isEqualApprox else @compileError("Vector.isEqualApprox requires a float vector");
            pub const isZeroApprox = if (is_float) H.isZeroApprox else @compileError("Vector.isZeroApprox requires a float vector");
            pub const isFinite = if (is_float) H.isFinite else @compileError("Vector.isFinite requires a float vector");
            pub const inverse = if (is_float) H.inverse else @compileError("Vector.inverse requires a float vector");
            pub const posmod = if (is_float) H.posmod else @compileError("Vector.posmod requires a float vector");
            pub const posmodv = if (is_float) H.posmodv else @compileError("Vector.posmodv requires a float vector");
            pub const project = if (is_float) H.project else @compileError("Vector.project requires a float vector");
            pub const lerp = if (is_float) H.lerp else @compileError("Vector.lerp requires a float vector");
            pub const slerp = if (is_float) H.slerp2 else @compileError("Vector.slerp requires a float vector");
            pub const cubicInterpolate = if (is_float) H.cubicInterpolate else @compileError("Vector.cubicInterpolate requires a float vector");
            pub const cubicInterpolateInTime = if (is_float) H.cubicInterpolateInTime else @compileError("Vector.cubicInterpolateInTime requires a float vector");
            pub const bezierInterpolate = if (is_float) H.bezierInterpolate else @compileError("Vector.bezierInterpolate requires a float vector");
            pub const bezierDerivative = if (is_float) H.bezierDerivative else @compileError("Vector.bezierDerivative requires a float vector");
            pub const moveToward = if (is_float) H.moveToward else @compileError("Vector.moveToward requires a float vector");
            pub const rotated = if (is_float) H.rotated2 else @compileError("Vector.rotated requires a float vector");
            pub const orthogonal = if (is_float) H.orthogonal2 else @compileError("Vector.orthogonal requires a float vector");
            pub const floor = if (is_float) H.floor else @compileError("Vector.floor requires a float vector");
            pub const ceil = if (is_float) H.ceil else @compileError("Vector.ceil requires a float vector");
            pub const round = if (is_float) H.round else @compileError("Vector.round requires a float vector");
            pub const dot = if (is_float) H.dot else @compileError("Vector.dot requires a float vector");
            pub const slide = if (is_float) H.slide else @compileError("Vector.slide requires a float vector");
            pub const bounce = if (is_float) H.bounce else @compileError("Vector.bounce requires a float vector");
            pub const reflect = if (is_float) H.reflect else @compileError("Vector.reflect requires a float vector");
            pub const cross = if (is_float) H.cross2 else @compileError("Vector.cross requires a float vector");
            pub const fromAngle = if (is_float) H.fromAngle2 else @compileError("Vector.fromAngle requires a float vector");

            pub const toBinding = H.toBinding;
            pub const fromBinding = H.fromBinding;

            pub const bindingCall = H.bindingCall;
            pub const bindingCallConst = H.bindingCallConst;
        },

        3 => extern struct {
            x: T,
            y: T,
            z: T,

            const Self = @This();
            const H = Helpers(Self);

            pub const Base = T;
            pub const is_float = t_is_float;
            pub const dimensions = dimension;
            pub const VecType = Vec;

            pub const Axis = if (is_float)
                bindings.builtins.Vector3.Axis
            else
                bindings.builtins.Vector3i.Axis;

            pub fn asVector(self: Self) Vec {
                return .{ self.x, self.y, self.z };
            }

            pub fn fromVector(value: Vec) Self {
                return .{ .x = value[0], .y = value[1], .z = value[2] };
            }

            pub const zero: Self = .fromVector(@splat(0));
            pub const one: Self = .fromVector(@splat(1));
            pub const inf: Self = if (is_float)
                .fromVector(@splat(std.math.inf(T)))
            else
                @compileError("Vector.inf is only available for float vectors");
            pub const minValue: Self = if (!is_float)
                .fromVector(@splat(std.math.minInt(T)))
            else
                @compileError("Vector.minValue is only available for integer vectors");
            pub const maxValue: Self = if (!is_float)
                .fromVector(@splat(std.math.maxInt(T)))
            else
                @compileError("Vector.maxValue is only available for integer vectors");

            pub const left: Self = .{ .x = -1, .y = 0, .z = 0 };
            pub const right: Self = .{ .x = 1, .y = 0, .z = 0 };
            pub const up: Self = .{ .x = 0, .y = 1, .z = 0 };
            pub const down: Self = .{ .x = 0, .y = -1, .z = 0 };
            pub const forward: Self = .{ .x = 0, .y = 0, .z = -1 };
            pub const back: Self = .{ .x = 0, .y = 0, .z = 1 };
            pub const modelLeft: Self = .{ .x = 1, .y = 0, .z = 0 };
            pub const modelRight: Self = .{ .x = -1, .y = 0, .z = 0 };
            pub const modelTop: Self = .{ .x = 0, .y = 1, .z = 0 };
            pub const modelBottom: Self = .{ .x = 0, .y = -1, .z = 0 };
            pub const modelFront: Self = .{ .x = 0, .y = 0, .z = 1 };
            pub const modelRear: Self = .{ .x = 0, .y = 0, .z = -1 };

            pub const add = H.add;
            pub const sub = H.sub;
            pub const mul = H.mul;
            pub const div = H.div;
            pub const scale = H.scale;
            pub const negate = H.negate;
            pub const abs = H.abs;
            pub const sign = H.sign;
            pub const min = H.min;
            pub const max = H.max;
            pub const clamp = H.clamp;
            pub const snapped = H.snapped;
            pub const minAxisIndex = H.minAxisIndex;
            pub const maxAxisIndex = H.maxAxisIndex;
            pub const length = H.length;
            pub const lengthSquared = H.lengthSquared;
            pub const distanceTo = H.distanceTo;
            pub const distanceSquaredTo = H.distanceSquaredTo;

            pub const minf = if (is_float) H.minf else @compileError("Vector.minf requires a float vector");
            pub const maxf = if (is_float) H.maxf else @compileError("Vector.maxf requires a float vector");
            pub const clampf = if (is_float) H.clampf else @compileError("Vector.clampf requires a float vector");
            pub const snappedf = if (is_float) H.snappedf else @compileError("Vector.snappedf requires a float vector");

            pub const mini = if (!is_float) H.mini else @compileError("Vector.mini requires an integer vector");
            pub const maxi = if (!is_float) H.maxi else @compileError("Vector.maxi requires an integer vector");
            pub const clampi = if (!is_float) H.clampi else @compileError("Vector.clampi requires an integer vector");
            pub const snappedi = if (!is_float) H.snappedi else @compileError("Vector.snappedi requires an integer vector");

            pub const angleTo = if (is_float) H.angleTo3 else @compileError("Vector.angleTo requires a float vector");
            pub const signedAngleTo = if (is_float) H.signedAngleTo3 else @compileError("Vector.signedAngleTo requires a float vector");
            pub const directionTo = if (is_float) H.directionTo else @compileError("Vector.directionTo requires a float vector");
            pub const limitLength = if (is_float) H.limitLength else @compileError("Vector.limitLength requires a float vector");
            pub const normalized = if (is_float) H.normalized else @compileError("Vector.normalized requires a float vector");
            pub const isNormalized = if (is_float) H.isNormalized else @compileError("Vector.isNormalized requires a float vector");
            pub const isEqualApprox = if (is_float) H.isEqualApprox else @compileError("Vector.isEqualApprox requires a float vector");
            pub const isZeroApprox = if (is_float) H.isZeroApprox else @compileError("Vector.isZeroApprox requires a float vector");
            pub const isFinite = if (is_float) H.isFinite else @compileError("Vector.isFinite requires a float vector");
            pub const inverse = if (is_float) H.inverse else @compileError("Vector.inverse requires a float vector");
            pub const rotated = if (is_float) H.rotated3 else @compileError("Vector.rotated requires a float vector");
            pub const lerp = if (is_float) H.lerp else @compileError("Vector.lerp requires a float vector");
            pub const slerp = if (is_float) H.slerp3 else @compileError("Vector.slerp requires a float vector");
            pub const cubicInterpolate = if (is_float) H.cubicInterpolate else @compileError("Vector.cubicInterpolate requires a float vector");
            pub const cubicInterpolateInTime = if (is_float) H.cubicInterpolateInTime else @compileError("Vector.cubicInterpolateInTime requires a float vector");
            pub const bezierInterpolate = if (is_float) H.bezierInterpolate else @compileError("Vector.bezierInterpolate requires a float vector");
            pub const bezierDerivative = if (is_float) H.bezierDerivative else @compileError("Vector.bezierDerivative requires a float vector");
            pub const moveToward = if (is_float) H.moveToward else @compileError("Vector.moveToward requires a float vector");
            pub const dot = if (is_float) H.dot else @compileError("Vector.dot requires a float vector");
            pub const cross = if (is_float) H.cross3 else @compileError("Vector.cross requires a float vector");
            pub const outer = if (is_float) H.outer3 else @compileError("Vector.outer requires a float vector");
            pub const floor = if (is_float) H.floor else @compileError("Vector.floor requires a float vector");
            pub const ceil = if (is_float) H.ceil else @compileError("Vector.ceil requires a float vector");
            pub const round = if (is_float) H.round else @compileError("Vector.round requires a float vector");
            pub const posmod = if (is_float) H.posmod else @compileError("Vector.posmod requires a float vector");
            pub const posmodv = if (is_float) H.posmodv else @compileError("Vector.posmodv requires a float vector");
            pub const project = if (is_float) H.project else @compileError("Vector.project requires a float vector");
            pub const slide = if (is_float) H.slide else @compileError("Vector.slide requires a float vector");
            pub const bounce = if (is_float) H.bounce else @compileError("Vector.bounce requires a float vector");
            pub const reflect = if (is_float) H.reflect else @compileError("Vector.reflect requires a float vector");
            pub const octahedronEncode = if (is_float) H.octahedronEncode3 else @compileError("Vector.octahedronEncode requires a float vector");
            pub const octahedronDecode = if (is_float) H.octahedronDecode3 else @compileError("Vector.octahedronDecode requires a float vector");

            pub const toBinding = H.toBinding;
            pub const fromBinding = H.fromBinding;

            pub const bindingCall = H.bindingCall;
            pub const bindingCallConst = H.bindingCallConst;
        },

        4 => extern struct {
            x: T,
            y: T,
            z: T,
            w: T,

            const Self = @This();
            const H = Helpers(Self);

            pub const Base = T;
            pub const is_float = t_is_float;
            pub const dimensions = dimension;
            pub const VecType = Vec;

            pub fn asVector(self: Self) Vec {
                return .{ self.x, self.y, self.z, self.w };
            }

            pub fn fromVector(value: Vec) Self {
                return .{ .x = value[0], .y = value[1], .z = value[2], .w = value[3] };
            }

            pub const zero: Self = .fromVector(@splat(0));
            pub const one: Self = .fromVector(@splat(1));
            pub const inf: Self = if (is_float)
                .fromVector(@splat(std.math.inf(T)))
            else
                @compileError("Vector.inf is only available for float vectors");
            pub const minValue: Self = if (!is_float)
                .fromVector(@splat(std.math.minInt(T)))
            else
                @compileError("Vector.minValue is only available for integer vectors");
            pub const maxValue: Self = if (!is_float)
                .fromVector(@splat(std.math.maxInt(T)))
            else
                @compileError("Vector.maxValue is only available for integer vectors");

            pub const add = H.add;
            pub const sub = H.sub;
            pub const mul = H.mul;
            pub const div = H.div;
            pub const scale = H.scale;
            pub const negate = H.negate;
            pub const abs = H.abs;
            pub const sign = H.sign;
            pub const min = H.min;
            pub const max = H.max;
            pub const clamp = H.clamp;
            pub const snapped = H.snapped;
            pub const minAxisIndex = H.minAxisIndex;
            pub const maxAxisIndex = H.maxAxisIndex;
            pub const length = H.length;
            pub const lengthSquared = H.lengthSquared;
            pub const distanceTo = H.distanceTo;
            pub const distanceSquaredTo = H.distanceSquaredTo;

            pub const minf = if (is_float) H.minf else @compileError("Vector.minf requires a float vector");
            pub const maxf = if (is_float) H.maxf else @compileError("Vector.maxf requires a float vector");
            pub const clampf = if (is_float) H.clampf else @compileError("Vector.clampf requires a float vector");
            pub const snappedf = if (is_float) H.snappedf else @compileError("Vector.snappedf requires a float vector");

            pub const mini = if (!is_float) H.mini else @compileError("Vector.mini requires an integer vector");
            pub const maxi = if (!is_float) H.maxi else @compileError("Vector.maxi requires an integer vector");
            pub const clampi = if (!is_float) H.clampi else @compileError("Vector.clampi requires an integer vector");
            pub const snappedi = if (!is_float) H.snappedi else @compileError("Vector.snappedi requires an integer vector");

            pub const directionTo = if (is_float) H.directionTo else @compileError("Vector.directionTo requires a float vector");
            pub const normalized = if (is_float) H.normalized else @compileError("Vector.normalized requires a float vector");
            pub const isNormalized = if (is_float) H.isNormalized else @compileError("Vector.isNormalized requires a float vector");
            pub const isEqualApprox = if (is_float) H.isEqualApprox else @compileError("Vector.isEqualApprox requires a float vector");
            pub const isZeroApprox = if (is_float) H.isZeroApprox else @compileError("Vector.isZeroApprox requires a float vector");
            pub const isFinite = if (is_float) H.isFinite else @compileError("Vector.isFinite requires a float vector");
            pub const inverse = if (is_float) H.inverse else @compileError("Vector.inverse requires a float vector");
            pub const lerp = if (is_float) H.lerp else @compileError("Vector.lerp requires a float vector");
            pub const cubicInterpolate = if (is_float) H.cubicInterpolate else @compileError("Vector.cubicInterpolate requires a float vector");
            pub const cubicInterpolateInTime = if (is_float) H.cubicInterpolateInTime else @compileError("Vector.cubicInterpolateInTime requires a float vector");
            pub const floor = if (is_float) H.floor else @compileError("Vector.floor requires a float vector");
            pub const ceil = if (is_float) H.ceil else @compileError("Vector.ceil requires a float vector");
            pub const round = if (is_float) H.round else @compileError("Vector.round requires a float vector");
            pub const posmod = if (is_float) H.posmod else @compileError("Vector.posmod requires a float vector");
            pub const posmodv = if (is_float) H.posmodv else @compileError("Vector.posmodv requires a float vector");
            pub const dot = if (is_float) H.dot else @compileError("Vector.dot requires a float vector");

            pub const toBinding = H.toBinding;
            pub const fromBinding = H.fromBinding;

            pub const bindingCall = H.bindingCall;
            pub const bindingCallConst = H.bindingCallConst;
        },

        else => unreachable,
    };
}

fn Helpers(comptime Self: type) type {
    return struct {
        const Vec = Self.VecType;
        const Base = Self.Base;
        const IsFloat = Self.is_float;
        const C = constants.For(Base);
        const Dim = Self.dimensions;
        const LengthT = if (IsFloat) Base else f64;
        const LengthSquaredT = if (IsFloat) Base else i64;
        const AspectT = if (IsFloat) Base else f32;

        fn splat(value: Base) Vec {
            return @splat(value);
        }

        pub fn add(self: Self, other: Self) Self {
            return .fromVector(self.asVector() + other.asVector());
        }

        pub fn sub(self: Self, other: Self) Self {
            return .fromVector(self.asVector() - other.asVector());
        }

        pub fn mul(self: Self, other: Self) Self {
            return .fromVector(self.asVector() * other.asVector());
        }

        pub fn div(self: Self, other: Self) Self {
            return .fromVector(self.asVector() / other.asVector());
        }

        pub fn scale(self: Self, scalar: Base) Self {
            return .fromVector(self.asVector() * splat(scalar));
        }

        pub fn negate(self: Self) Self {
            return .fromVector(-self.asVector());
        }

        pub fn abs(self: Self) Self {
            if (comptime IsFloat) return .fromVector(@abs(self.asVector()));
            return .fromVector(@as(Vec, @intCast(@abs(self.asVector()))));
        }

        pub fn sign(self: Self) Self {
            const value = self.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = if (value[i] > 0) 1 else if (value[i] < 0) -1 else 0;
            }
            return .fromVector(result);
        }

        pub fn min(self: Self, other: Self) Self {
            return .fromVector(@min(self.asVector(), other.asVector()));
        }

        pub fn max(self: Self, other: Self) Self {
            return .fromVector(@max(self.asVector(), other.asVector()));
        }

        pub fn minf(self: Self, scalar: Base) Self {
            return .fromVector(@min(self.asVector(), splat(scalar)));
        }

        pub fn maxf(self: Self, scalar: Base) Self {
            return .fromVector(@max(self.asVector(), splat(scalar)));
        }

        pub fn mini(self: Self, scalar: Base) Self {
            return .fromVector(@min(self.asVector(), splat(scalar)));
        }

        pub fn maxi(self: Self, scalar: Base) Self {
            return .fromVector(@max(self.asVector(), splat(scalar)));
        }

        pub fn clamp(self: Self, min_value: Self, max_value: Self) Self {
            return .fromVector(@min(@max(self.asVector(), min_value.asVector()), max_value.asVector()));
        }

        pub fn clampf(self: Self, min_value: Base, max_value: Base) Self {
            return .fromVector(@min(@max(self.asVector(), splat(min_value)), splat(max_value)));
        }

        pub fn clampi(self: Self, min_value: Base, max_value: Base) Self {
            return .fromVector(@min(@max(self.asVector(), splat(min_value)), splat(max_value)));
        }

        pub fn snapped(self: Self, step: Self) Self {
            const value = self.asVector();
            const step_value = step.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = snappedScalar(value[i], step_value[i]);
            }
            return .fromVector(result);
        }

        pub fn snappedf(self: Self, step: Base) Self {
            const value = self.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = snappedScalar(value[i], step);
            }
            return .fromVector(result);
        }

        pub fn snappedi(self: Self, step: Base) Self {
            const value = self.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = snappedScalar(value[i], step);
            }
            return .fromVector(result);
        }

        fn snappedScalar(value: Base, step: Base) Base {
            if (step == 0) return value;

            if (comptime IsFloat) {
                const v: f64 = @floatCast(value);
                const s: f64 = @floatCast(step);
                return @floatCast(@floor(v / s + 0.5) * s);
            }

            const v: f64 = @floatFromInt(value);
            const s: f64 = @floatFromInt(step);
            return @intFromFloat(@floor(v / s + 0.5) * s);
        }

        pub fn minAxisIndex(self: Self) usize {
            const value = self.asVector();
            return switch (Dim) {
                2 => if (value[0] < value[1]) 0 else 1,
                3 => if (value[0] < value[1])
                    (if (value[0] < value[2]) 0 else 2)
                else
                    (if (value[1] < value[2]) 1 else 2),
                4 => blk: {
                    var index: usize = 0;
                    var minimum = value[0];
                    inline for (1..4) |i| {
                        if (value[i] <= minimum) {
                            index = i;
                            minimum = value[i];
                        }
                    }
                    break :blk index;
                },
                else => unreachable,
            };
        }

        pub fn maxAxisIndex(self: Self) usize {
            const value = self.asVector();
            return switch (Dim) {
                2 => if (value[0] < value[1]) 1 else 0,
                3 => if (value[0] < value[1])
                    (if (value[1] < value[2]) 2 else 1)
                else
                    (if (value[0] < value[2]) 2 else 0),
                4 => blk: {
                    var index: usize = 0;
                    var maximum = value[0];
                    inline for (1..4) |i| {
                        if (value[i] > maximum) {
                            index = i;
                            maximum = value[i];
                        }
                    }
                    break :blk index;
                },
                else => unreachable,
            };
        }

        pub fn lengthSquared(self: Self) LengthSquaredT {
            const value = self.asVector();
            if (comptime IsFloat) return @reduce(.Add, value * value);

            const wide: @Vector(Dim, i64) = value;
            return @reduce(.Add, wide * wide);
        }

        pub fn length(self: Self) LengthT {
            if (comptime IsFloat) return @sqrt(self.lengthSquared());
            return @sqrt(@as(f64, @floatFromInt(self.lengthSquared())));
        }

        pub fn dot(self: Self, other: Self) Base {
            return @reduce(.Add, self.asVector() * other.asVector());
        }

        pub fn distanceTo(self: Self, to: Self) LengthT {
            return self.sub(to).length();
        }

        pub fn distanceSquaredTo(self: Self, to: Self) LengthSquaredT {
            return self.sub(to).lengthSquared();
        }

        pub fn directionTo(self: Self, to: Self) Self {
            return to.sub(self).normalized();
        }

        pub fn normalized(self: Self) Self {
            if (!self.isFinite()) return Self.zero;

            const length_squared = self.lengthSquared();
            if (length_squared == 0) return Self.zero;

            return .fromVector(self.asVector() / splat(@sqrt(length_squared)));
        }

        pub fn isNormalized(self: Self) bool {
            // Use length_squared() to avoid sqrt, matching Godot. Godot's default
            return isEqualApproxTolerance(self.lengthSquared(), 1, C.unit_epsilon);
        }

        pub fn isEqualApprox(self: Self, to: Self) bool {
            const a = self.asVector();
            const b = to.asVector();
            const exact = a == b;
            const tolerance = @max(@abs(a) * splat(C.cmp_epsilon), splat(C.cmp_epsilon));
            return @reduce(.And, exact | (@abs(a - b) < tolerance));
        }

        pub fn isZeroApprox(self: Self) bool {
            return @reduce(.And, @abs(self.asVector()) < splat(C.cmp_epsilon));
        }

        pub fn isFinite(self: Self) bool {
            return @reduce(.And, @abs(self.asVector()) < splat(std.math.inf(Base)));
        }

        pub fn inverse(self: Self) Self {
            return .fromVector(splat(1) / self.asVector());
        }

        pub fn floor(self: Self) Self {
            return .fromVector(@floor(self.asVector()));
        }

        pub fn ceil(self: Self) Self {
            return .fromVector(@ceil(self.asVector()));
        }

        pub fn round(self: Self) Self {
            return .fromVector(@round(self.asVector()));
        }

        pub fn posmod(self: Self, modulus: Base) Self {
            return .fromVector(@mod(self.asVector(), splat(modulus)));
        }

        pub fn posmodv(self: Self, modulus: Self) Self {
            return .fromVector(@mod(self.asVector(), modulus.asVector()));
        }

        pub fn project(self: Self, to: Self) Self {
            return scale(to, dot(self, to) / lengthSquared(to));
        }

        pub fn lerp(self: Self, to: Self, weight: Base) Self {
            return add(self, scale(sub(to, self), weight));
        }

        pub fn slerp2(self: Self, to: Self, weight: Base) Self {
            const start_length_squared = lengthSquared(self);
            const end_length_squared = lengthSquared(to);
            if (start_length_squared == 0 or end_length_squared == 0) {
                return lerp(self, to, weight);
            }

            const start_length = @sqrt(start_length_squared);
            const result_length = lerpScalar(start_length, @sqrt(end_length_squared), weight);
            const angle = angleTo2(self, to);
            return scale(rotated2(self, angle * weight), result_length / start_length);
        }

        pub fn slerp3(self: Self, to: Self, weight: Base) Self {
            const start_length_squared = lengthSquared(self);
            const end_length_squared = lengthSquared(to);
            if (start_length_squared == 0 or end_length_squared == 0) {
                return lerp(self, to, weight);
            }

            const axis = cross3(self, to);
            const axis_length_squared = lengthSquared(axis);
            if (axis_length_squared == 0) {
                return lerp(self, to, weight);
            }

            const normalized_axis = scale(axis, 1 / @sqrt(axis_length_squared));
            const start_length = @sqrt(start_length_squared);
            const result_length = lerpScalar(start_length, @sqrt(end_length_squared), weight);
            const angle = angleTo3(self, to);
            return scale(rotated3(self, normalized_axis, angle * weight), result_length / start_length);
        }

        pub fn cubicInterpolate(self: Self, to: Self, pre_a: Self, post_b: Self, weight: Base) Self {
            const a = self.asVector();
            const b = to.asVector();
            const pre = pre_a.asVector();
            const post = post_b.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = cubicScalar(a[i], b[i], pre[i], post[i], weight);
            }
            return .fromVector(result);
        }

        pub fn cubicInterpolateInTime(
            self: Self,
            to: Self,
            pre_a: Self,
            post_b: Self,
            weight: Base,
            to_time: Base,
            pre_a_time: Base,
            post_b_time: Base,
        ) Self {
            const a = self.asVector();
            const b = to.asVector();
            const pre = pre_a.asVector();
            const post = post_b.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = cubicInTimeScalar(a[i], b[i], pre[i], post[i], weight, to_time, pre_a_time, post_b_time);
            }
            return .fromVector(result);
        }

        pub fn bezierInterpolate(self: Self, control_1: Self, control_2: Self, end: Self, t: Base) Self {
            const a = self.asVector();
            const c1 = control_1.asVector();
            const c2 = control_2.asVector();
            const e = end.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = bezierScalar(a[i], c1[i], c2[i], e[i], t);
            }
            return .fromVector(result);
        }

        pub fn bezierDerivative(self: Self, control_1: Self, control_2: Self, end: Self, t: Base) Self {
            const a = self.asVector();
            const c1 = control_1.asVector();
            const c2 = control_2.asVector();
            const e = end.asVector();
            var result: Vec = undefined;
            inline for (0..Dim) |i| {
                result[i] = bezierDerivativeScalar(a[i], c1[i], c2[i], e[i], t);
            }
            return .fromVector(result);
        }

        pub fn moveToward(self: Self, to: Self, delta: Base) Self {
            const difference = to.sub(self);
            const distance = difference.length();
            if (distance <= delta or distance < C.cmp_epsilon) return to;
            return self.add(difference.scale(delta / distance));
        }

        pub fn limitLength(self: Self, max_length: Base) Self {
            const current_length = self.length();
            if (current_length > 0 and max_length < current_length) {
                return self.scale(max_length / current_length);
            }
            return self;
        }

        pub fn slide(self: Self, normal: Self) Self {
            return self.sub(normal.scale(self.dot(normal)));
        }

        pub fn bounce(self: Self, normal: Self) Self {
            return self.reflect(normal).negate();
        }

        pub fn reflect(self: Self, normal: Self) Self {
            return normal.scale(2 * self.dot(normal)).sub(self);
        }

        pub fn aspect(self: Self) AspectT {
            if (comptime IsFloat) return self.x / self.y;
            return @as(f32, @floatFromInt(self.x)) / @as(f32, @floatFromInt(self.y));
        }

        pub fn angle2(self: Self) Base {
            return std.math.atan2(self.y, self.x);
        }

        pub fn angleTo2(self: Self, to: Self) Base {
            return std.math.atan2(cross2(self, to), dot(self, to));
        }

        pub fn angleToPoint2(self: Self, to: Self) Base {
            return angle2(sub(to, self));
        }

        pub fn cross2(self: Self, other: Self) Base {
            return self.x * other.y - self.y * other.x;
        }

        pub fn orthogonal2(self: Self) Self {
            return .fromVector(.{ self.y, -self.x });
        }

        pub fn rotated2(self: Self, angle: Base) Self {
            const sine = @sin(angle);
            const cosine = @cos(angle);
            return .fromVector(.{
                self.x * cosine - self.y * sine,
                self.x * sine + self.y * cosine,
            });
        }

        pub fn fromAngle2(angle: Base) Self {
            return .fromVector(.{ @cos(angle), @sin(angle) });
        }

        pub fn angleTo3(self: Self, to: Self) Base {
            return std.math.atan2(length(cross3(self, to)), dot(self, to));
        }

        pub fn signedAngleTo3(self: Self, to: Self, axis: Self) Base {
            const cross_to = cross3(self, to);
            const unsigned_angle = std.math.atan2(length(cross_to), dot(self, to));
            return if (dot(cross_to, axis) < 0) -unsigned_angle else unsigned_angle;
        }

        pub fn cross3(self: Self, other: Self) Self {
            return .fromVector(.{
                self.y * other.z - self.z * other.y,
                self.z * other.x - self.x * other.z,
                self.x * other.y - self.y * other.x,
            });
        }

        pub fn rotated3(self: Self, axis: Self, angle: Base) Self {
            const cosine = @cos(angle);
            const sine = @sin(angle);
            const t = 1 - cosine;

            const axis_sq_x = axis.x * axis.x;
            const axis_sq_y = axis.y * axis.y;
            const axis_sq_z = axis.z * axis.z;

            const r00 = axis_sq_x + cosine * (1 - axis_sq_x);
            const r11 = axis_sq_y + cosine * (1 - axis_sq_y);
            const r22 = axis_sq_z + cosine * (1 - axis_sq_z);

            const xyzt = axis.x * axis.y * t;
            const zyxs = axis.z * sine;
            const r01 = xyzt - zyxs;
            const r10 = xyzt + zyxs;

            const xzyt = axis.x * axis.z * t;
            const yzxs = axis.y * sine;
            const r02 = xzyt + yzxs;
            const r20 = xzyt - yzxs;

            const yzzt = axis.y * axis.z * t;
            const xzys = axis.x * sine;
            const r12 = yzzt - xzys;
            const r21 = yzzt + xzys;

            const value = self.asVector();
            return .fromVector(.{
                value[0] * r00 + value[1] * r01 + value[2] * r02,
                value[0] * r10 + value[1] * r11 + value[2] * r12,
                value[0] * r20 + value[1] * r21 + value[2] * r22,
            });
        }

        pub fn outer3(self: Self, with: Self) basis_mod.BasisOf(Base) {
            return .{ .rows = .{
                .{ .x = self.x * with.x, .y = self.x * with.y, .z = self.x * with.z },
                .{ .x = self.y * with.x, .y = self.y * with.y, .z = self.y * with.z },
                .{ .x = self.z * with.x, .y = self.z * with.y, .z = self.z * with.z },
            } };
        }

        pub fn octahedronEncode3(self: Self) GenericVector(Base, 2, IsFloat) {
            const V2 = GenericVector(Base, 2, IsFloat);
            const n = self.scale(1 / (@abs(self.x) + @abs(self.y) + @abs(self.z)));

            var x: Base = undefined;
            var y: Base = undefined;
            if (n.z >= 0) {
                x = n.x;
                y = n.y;
            } else {
                x = (1 - @abs(n.y)) * (if (n.x >= 0) @as(Base, 1) else @as(Base, -1));
                y = (1 - @abs(n.x)) * (if (n.y >= 0) @as(Base, 1) else @as(Base, -1));
            }

            return V2.fromVector(.{ x * 0.5 + 0.5, y * 0.5 + 0.5 });
        }

        pub fn octahedronDecode3(oct: GenericVector(Base, 2, IsFloat)) Self {
            const f_x = oct.x * 2 - 1;
            const f_y = oct.y * 2 - 1;
            var n = Self.fromVector(.{ f_x, f_y, 1 - @abs(f_x) - @abs(f_y) });

            const t = std.math.clamp(-n.z, 0, 1);
            n.x += if (n.x >= 0) -t else t;
            n.y += if (n.y >= 0) -t else t;
            return n.normalized();
        }

        fn lerpScalar(from: Base, to: Base, weight: Base) Base {
            return from + (to - from) * weight;
        }

        fn cubicScalar(from: Base, to: Base, pre: Base, post: Base, weight: Base) Base {
            return 0.5 *
                ((from * 2) +
                    (-pre + to) * weight +
                    (2 * pre - 5 * from + 4 * to - post) * (weight * weight) +
                    (-pre + 3 * from - 3 * to + post) * (weight * weight * weight));
        }

        fn cubicInTimeScalar(
            from: Base,
            to: Base,
            pre: Base,
            post: Base,
            weight: Base,
            to_time: Base,
            pre_time: Base,
            post_time: Base,
        ) Base {
            const t = lerpScalar(0, to_time, weight);
            const a1 = lerpScalar(pre, from, if (pre_time == 0) 0 else (t - pre_time) / -pre_time);
            const a2 = lerpScalar(from, to, if (to_time == 0) 0.5 else t / to_time);
            const a3 = lerpScalar(to, post, if (post_time - to_time == 0) 1 else (t - to_time) / (post_time - to_time));
            const b1 = lerpScalar(a1, a2, if (to_time - pre_time == 0) 0 else (t - pre_time) / (to_time - pre_time));
            const b2 = lerpScalar(a2, a3, if (post_time == 0) 1 else t / post_time);
            return lerpScalar(b1, b2, if (to_time == 0) 0.5 else t / to_time);
        }

        fn bezierScalar(start: Base, control_1: Base, control_2: Base, end: Base, t: Base) Base {
            const omt = 1 - t;
            const omt2 = omt * omt;
            const omt3 = omt2 * omt;
            const t2 = t * t;
            const t3 = t2 * t;
            return start * omt3 + control_1 * omt2 * t * 3 + control_2 * omt * t2 * 3 + end * t3;
        }

        fn bezierDerivativeScalar(start: Base, control_1: Base, control_2: Base, end: Base, t: Base) Base {
            const omt = 1 - t;
            const omt2 = omt * omt;
            const t2 = t * t;
            return (control_1 - start) * 3 * omt2 + (control_2 - control_1) * 6 * omt * t + (end - control_2) * 3 * t2;
        }

        fn isEqualApproxScalar(a: Base, b: Base) bool {
            if (a == b) return true;

            var tolerance: Base = C.cmp_epsilon * @abs(a);
            if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
            return @abs(a - b) < tolerance;
        }

        fn isEqualApproxTolerance(a: Base, b: Base, tolerance: Base) bool {
            if (a == b) return true;
            return @abs(a - b) < tolerance;
        }

        const BindingT = switch (Dim) {
            2 => if (IsFloat) bindings.builtins.Vector2 else bindings.builtins.Vector2i,
            3 => if (IsFloat) bindings.builtins.Vector3 else bindings.builtins.Vector3i,
            4 => if (IsFloat) bindings.builtins.Vector4 else bindings.builtins.Vector4i,
            else => @compileError("Unsupported dimension."),
        };

        const generated_namespace = switch (Dim) {
            2 => if (IsFloat) @import("generated/vector2.zig") else @import("generated/vector2i.zig"),
            3 => if (IsFloat) @import("generated/vector3.zig") else @import("generated/vector3i.zig"),
            4 => if (IsFloat) @import("generated/vector4.zig") else @import("generated/vector4i.zig"),
            else => @compileError("Unsupported dimension."),
        };

        pub fn toBinding(self: *const Self) BindingT {
            return @as(*const BindingT, @ptrCast(self)).*;
        }

        pub fn fromBinding(v: BindingT) Self {
            return @as(*const Self, @ptrCast(&v)).*;
        }

        pub inline fn bindingCall(
            self: *Self,
            comptime function: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_namespace.MemberFunctions, function)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, function)) {
            const func = auto.FunctionOf(generated_namespace, function);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallConst(
            self: *const Self,
            comptime function: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_namespace.MemberFunctions, function)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, function)) {
            const func = auto.FunctionOf(generated_namespace, function);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallStatic(
            comptime function: @EnumLiteral(),
            args: auto.FunctionArgsAsTuple(auto.FunctionOf(generated_namespace.StaticFunctions, function)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_namespace, function)) {
            const func = auto.FunctionOf(generated_namespace, function);
            return @call(.auto, func, args);
        }
    };
}

const SingleVector2 = Vector(f32, 2);
const SingleVector3 = Vector(f32, 3);
const SingleVector4 = Vector(f32, 4);

const DoubleVector2 = Vector(f64, 2);
const DoubleVector3 = Vector(f64, 3);
const DoubleVector4 = Vector(f64, 4);

const IntVector2 = Vector(i32, 2);
const IntVector3 = Vector(i32, 3);
const IntVector4 = Vector(i32, 4);

/// Single precision (`real_t = float`) builtins, matching a default Godot build.
pub const single = struct {
    pub const real_t = f32;
    pub const Basis = basis_mod.BasisOf(f32);
    pub const Vector2 = SingleVector2;
    pub const Vector2i = IntVector2;
    pub const Vector3 = SingleVector3;
    pub const Vector3i = IntVector3;
    pub const Vector4 = SingleVector4;
    pub const Vector4i = IntVector4;
};

/// Double precision (`real_t = double`) builtins, matching a `precision=double`
/// Godot build.
pub const double = struct {
    pub const real_t = f64;
    pub const Basis = basis_mod.BasisOf(f64);
    pub const Vector2 = DoubleVector2;
    pub const Vector2i = IntVector2;
    pub const Vector3 = DoubleVector3;
    pub const Vector3i = IntVector3;
    pub const Vector4 = DoubleVector4;
    pub const Vector4i = IntVector4;
};

const precision = if (bindings.is_double_precision) double else single;
pub const real_t = precision.real_t;
pub const Basis = precision.Basis;
pub const Vector2 = precision.Vector2;
pub const Vector2i = precision.Vector2i;
pub const Vector3 = precision.Vector3;
pub const Vector3i = precision.Vector3i;
pub const Vector4 = precision.Vector4;
pub const Vector4i = precision.Vector4i;

test "vector constants match the engine" {
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = 0 }, single.Vector2.zero);
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = -1 }, single.Vector2.up);
    try std.testing.expectEqual(single.Vector2{ .x = 0, .y = 1 }, single.Vector2.down);
    try std.testing.expectEqual(single.Vector3{ .x = 0, .y = 0, .z = -1 }, single.Vector3.forward);
    try std.testing.expectEqual(single.Vector3{ .x = 0, .y = 0, .z = 1 }, single.Vector3.back);
    try std.testing.expectEqual(single.Vector2i{ .x = -2147483648, .y = -2147483648 }, single.Vector2i.minValue);
    try std.testing.expectEqual(single.Vector4{ .x = 1, .y = 1, .z = 1, .w = 1 }, single.Vector4.one);
}

test "float vector basics" {
    const a = single.Vector2{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f32, 5), a.length());
    try std.testing.expectEqual(@as(f32, 25), a.lengthSquared());
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), a.normalized().x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), a.normalized().y, 0.00001);
    try std.testing.expect(a.normalized().isNormalized());

    const b = single.Vector2{ .x = 1, .y = 2 };
    try std.testing.expectEqual(@as(f32, 11), a.dot(b));
    try std.testing.expectEqual(@as(f32, 2), a.cross(b));
    try std.testing.expectApproxEqAbs(@as(f32, 2.828427), a.distanceTo(b), 0.00001);

    try std.testing.expectEqual(single.Vector2{ .x = 4, .y = 6 }, a.add(b));
    try std.testing.expectEqual(single.Vector2{ .x = 2, .y = 2 }, a.sub(b));
    try std.testing.expectEqual(single.Vector2{ .x = 3, .y = 8 }, a.mul(b));
    try std.testing.expectEqual(single.Vector2{ .x = 3, .y = 2 }, a.div(b));
}

test "vector rotation and angles" {
    const rotated = (single.Vector2{ .x = 1, .y = 0 }).rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rotated.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), rotated.y, 0.00001);

    const from_angle = single.Vector2.fromAngle(0);
    try std.testing.expectEqual(single.Vector2{ .x = 1, .y = 0 }, from_angle);

    const v3 = (single.Vector3{ .x = 1, .y = 0, .z = 0 }).rotated(single.Vector3.back, std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v3.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v3.y, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v3.z, 0.00001);
}

test "integer vector methods" {
    const a = single.Vector2i{ .x = -3, .y = 7 };
    try std.testing.expectApproxEqAbs(@as(f32, -0.42857143), a.aspect(), 0.00001);
    try std.testing.expectEqual(single.Vector2i{ .x = 0, .y = 2 }, a.clamp(single.Vector2i.zero, single.Vector2i{ .x = 2, .y = 2 }));
    try std.testing.expectEqual(single.Vector2i{ .x = 0, .y = 2 }, a.clampi(0, 2));
    try std.testing.expectEqual(single.Vector2i{ .x = -2, .y = 8 }, a.snapped(single.Vector2i{ .x = 2, .y = 4 }));
    try std.testing.expectEqual(@as(i64, 58), a.lengthSquared());
    try std.testing.expectEqual(single.Vector3i{ .x = 3, .y = 7, .z = 1 }, (single.Vector3i{ .x = -3, .y = 7, .z = -1 }).abs());
    try std.testing.expectEqual(@as(i64, 59), (single.Vector3i{ .x = -3, .y = 7, .z = -1 }).lengthSquared());
}

test "vector interpolation" {
    const a = single.Vector2.zero;
    const b = single.Vector2.one;
    try std.testing.expectEqual(single.Vector2{ .x = 0.5, .y = 0.5 }, a.lerp(b, 0.5));

    const cubic = a.cubicInterpolate(b, a, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubic.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cubic.y, 0.00001);

    const bezier = a.bezierInterpolate(a, b, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bezier.x, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bezier.y, 0.00001);
}

test "octahedron round trip" {
    const values = [_]single.Vector3{
        single.Vector3{ .x = 0, .y = 0, .z = 1 },
        single.Vector3{ .x = 1, .y = 0, .z = 0 },
        single.Vector3{ .x = -1, .y = 0, .z = 0 },
        (single.Vector3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized(),
    };

    for (values) |value| {
        const encoded = value.octahedronEncode();
        const decoded = single.Vector3.octahedronDecode(encoded);
        try std.testing.expect(decoded.isEqualApprox(value));
    }
}

test "outer product" {
    const a = single.Vector3{ .x = 1, .y = 2, .z = 3 };
    const b = single.Vector3{ .x = 4, .y = 5, .z = 6 };
    const basis = a.outer(b);
    try std.testing.expectEqual(single.Vector3{ .x = 4, .y = 5, .z = 6 }, basis.rows[0]);
    try std.testing.expectEqual(single.Vector3{ .x = 8, .y = 10, .z = 12 }, basis.rows[1]);
    try std.testing.expectEqual(single.Vector3{ .x = 12, .y = 15, .z = 18 }, basis.rows[2]);
}

test "vector layout matches the GDExtension ABI" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(single.Vector2));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(single.Vector2i));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(single.Vector3));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(single.Vector3i));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Vector4));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Vector4i));

    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Vector2));
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(single.Basis));
}

fn checkVector2Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2 };
    const b: V = .{ .x = 3, .y = 4 };

    std.mem.doNotOptimizeAway(a.angle());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.angleToPoint(b));
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.limitLength(1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.project(b));
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.bezierInterpolate(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.bezierDerivative(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.moveToward(b, 0.5));
    std.mem.doNotOptimizeAway(a.rotated(0.5));
    std.mem.doNotOptimizeAway(a.orthogonal());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.aspect());
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.slide(b));
    std.mem.doNotOptimizeAway(a.bounce(b));
    std.mem.doNotOptimizeAway(a.reflect(b));
    std.mem.doNotOptimizeAway(a.cross(b));
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
    std.mem.doNotOptimizeAway(V.fromAngle(1));
}

test "double precision aliases and layout" {
    try std.testing.expect(single.real_t == f32);
    try std.testing.expect(double.real_t == f64);

    // Integer vectors are precision independent and shared between namespaces.
    try std.testing.expect(double.Vector2i == single.Vector2i);

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(double.Vector2));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(double.Vector3));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(double.Vector4));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(double.Basis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Vector2));
}

test "double precision math" {
    const V2 = double.Vector2;
    const V3 = double.Vector3;
    const V4 = double.Vector4;

    const a: V2 = .{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f64, 5), a.length());
    try std.testing.expectEqual(@as(f64, 25), a.lengthSquared());
    try std.testing.expect(a.normalized().isNormalized());

    const rotated = (V2{ .x = 1, .y = 0 }).rotated(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1), rotated.y, 1e-12);

    const cross = (V3{ .x = 1, .y = 0, .z = 0 }).cross(.{ .x = 0, .y = 1, .z = 0 });
    try std.testing.expectEqual(V3{ .x = 0, .y = 0, .z = 1 }, cross);

    const basis = (V3{ .x = 1, .y = 2, .z = 3 }).outer(.{ .x = 4, .y = 5, .z = 6 });
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(@TypeOf(basis)));
    try std.testing.expectEqual(V3{ .x = 4, .y = 5, .z = 6 }, basis.rows[0]);

    const lerped = (V4{ .x = 0, .y = 0, .z = 0, .w = 0 }).lerp(.{ .x = 1, .y = 1, .z = 1, .w = 1 }, 0.5);
    try std.testing.expectEqual(V4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, lerped);

    const decoded = V3.octahedronDecode((V3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized().octahedronEncode());
    try std.testing.expect(decoded.isEqualApprox((V3{ .x = 0.3, .y = -0.4, .z = 0.5 }).normalized()));
}

test "all Vector2 float methods compile" {
    checkVector2Float(single.Vector2);
    checkVector2Float(double.Vector2);
}

fn checkVector2i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7 };
    const b: V = .{ .x = 2, .y = 4 };

    std.mem.doNotOptimizeAway(a.aspect());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
}

test "all Vector2i methods compile" {
    checkVector2i(single.Vector2i);
}

fn checkVector3Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2, .z = 3 };
    const b: V = .{ .x = 3, .y = 4, .z = 5 };
    const axis: V = .{ .x = 0, .y = 0, .z = 1 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.angleTo(b));
    std.mem.doNotOptimizeAway(a.signedAngleTo(b, axis));
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.limitLength(1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.rotated(axis, 0.5));
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.slerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.bezierInterpolate(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.bezierDerivative(V.zero, V.one, b, 0.5));
    std.mem.doNotOptimizeAway(a.moveToward(b, 0.5));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.cross(b));
    std.mem.doNotOptimizeAway(a.outer(b).xform(a));
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.project(b));
    std.mem.doNotOptimizeAway(a.slide(b));
    std.mem.doNotOptimizeAway(a.bounce(b));
    std.mem.doNotOptimizeAway(a.reflect(b));
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.octahedronEncode());
    std.mem.doNotOptimizeAway(V.octahedronDecode(a.octahedronEncode()));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
}

test "all Vector3 float methods compile" {
    checkVector3Float(single.Vector3);
    checkVector3Float(double.Vector3);
}

fn checkVector3i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7, .z = 1 };
    const b: V = .{ .x = 2, .y = 4, .z = 6 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
}

test "all Vector3i methods compile" {
    checkVector3i(single.Vector3i);
}

fn checkVector4Float(comptime V: type) void {
    const a: V = .{ .x = 1, .y = 2, .z = 3, .w = 4 };
    const b: V = .{ .x = 3, .y = 4, .z = 5, .w = 6 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.floor());
    std.mem.doNotOptimizeAway(a.ceil());
    std.mem.doNotOptimizeAway(a.round());
    std.mem.doNotOptimizeAway(a.lerp(b, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolate(b, V.zero, V.one, 0.5));
    std.mem.doNotOptimizeAway(a.cubicInterpolateInTime(b, V.zero, V.one, 0.5, 1, 0, 2));
    std.mem.doNotOptimizeAway(a.posmod(2));
    std.mem.doNotOptimizeAway(a.posmodv(b));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedf(0.5));
    std.mem.doNotOptimizeAway(a.clamp(V.zero, V.one));
    std.mem.doNotOptimizeAway(a.clampf(0, 1));
    std.mem.doNotOptimizeAway(a.normalized());
    std.mem.doNotOptimizeAway(a.isNormalized());
    std.mem.doNotOptimizeAway(a.directionTo(b));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
    std.mem.doNotOptimizeAway(a.dot(b));
    std.mem.doNotOptimizeAway(a.inverse());
    std.mem.doNotOptimizeAway(a.isEqualApprox(b));
    std.mem.doNotOptimizeAway(a.isZeroApprox());
    std.mem.doNotOptimizeAway(a.isFinite());
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.minf(0));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxf(0));
}

test "all Vector4 float methods compile" {
    checkVector4Float(single.Vector4);
    checkVector4Float(double.Vector4);
}

fn checkVector4i(comptime V: type) void {
    const a: V = .{ .x = -3, .y = 7, .z = 1, .w = 2 };
    const b: V = .{ .x = 2, .y = 4, .z = 6, .w = 8 };

    std.mem.doNotOptimizeAway(a.minAxisIndex());
    std.mem.doNotOptimizeAway(a.maxAxisIndex());
    std.mem.doNotOptimizeAway(a.length());
    std.mem.doNotOptimizeAway(a.lengthSquared());
    std.mem.doNotOptimizeAway(a.sign());
    std.mem.doNotOptimizeAway(a.abs());
    std.mem.doNotOptimizeAway(a.clamp(V.zero, b));
    std.mem.doNotOptimizeAway(a.clampi(0, 2));
    std.mem.doNotOptimizeAway(a.snapped(b));
    std.mem.doNotOptimizeAway(a.snappedi(2));
    std.mem.doNotOptimizeAway(a.min(b));
    std.mem.doNotOptimizeAway(a.mini(2));
    std.mem.doNotOptimizeAway(a.max(b));
    std.mem.doNotOptimizeAway(a.maxi(2));
    std.mem.doNotOptimizeAway(a.distanceTo(b));
    std.mem.doNotOptimizeAway(a.distanceSquaredTo(b));
}

test "all Vector4i methods compile" {
    checkVector4i(single.Vector4i);
}

const std = @import("std");

const basis_mod = @import("basis.zig");
const constants = @import("constants.zig");

const auto = @import("../auto/auto.zig");

const bindings = @import("bindings");
