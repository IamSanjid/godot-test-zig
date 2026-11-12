//! Pure-Zig implementations of Godot's `Rect2` and `Rect2i` builtins.
//!
//! Both live in this module because they share the same shape and method set.
//! `Rect2` is generic over the real type; `Rect2i` is always 32-bit integers and
//! is shared between the `single` and `double` namespaces.

pub const Side = enum(u2) {
    left,
    top,
    right,
    bottom,
};

pub fn Rect2Of(comptime Real: type) type {
    const V2 = vector.Vector(Real, 2);

    return extern struct {
        position: V2 = .zero,
        size: V2 = .zero,

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Rect2 {
            return @as(*const bindings.builtins.Rect2, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Rect2 => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Rect2 => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Rect2 => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Rect2 by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub inline fn bindingCall(
            self: *Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_rect2_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallConst(
            self: *const Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_rect2_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallStatic(
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTuple(auto.FunctionOf(generated_rect2_namespace.StaticFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2_namespace, method);
            return @call(.auto, func, args);
        }

        pub fn init(position: V2, size: V2) Self {
            return .{ .position = position, .size = size };
        }

        pub fn getCenter(self: Self) V2 {
            return self.position.add(self.size.scale(0.5));
        }

        pub fn getEnd(self: Self) V2 {
            return self.position.add(self.size);
        }

        pub fn setEnd(self: *Self, end: V2) void {
            self.size = end.sub(self.position);
        }

        pub fn getArea(self: Self) Real {
            return self.size.x * self.size.y;
        }

        pub fn hasArea(self: Self) bool {
            return self.size.x > 0 and self.size.y > 0;
        }

        pub fn hasPoint(self: Self, point: V2) bool {
            if (point.x < self.position.x or point.y < self.position.y) return false;
            if (point.x >= self.position.x + self.size.x) return false;
            if (point.y >= self.position.y + self.size.y) return false;
            return true;
        }

        pub fn isEqualApprox(self: Self, other: Self) bool {
            return self.position.isEqualApprox(other.position) and self.size.isEqualApprox(other.size);
        }

        pub fn isFinite(self: Self) bool {
            return self.position.isFinite() and self.size.isFinite();
        }

        pub fn intersects(self: Self, other: Self, include_borders: bool) bool {
            const other_end = other.position.add(other.size);
            const end = self.position.add(self.size);

            if (include_borders) {
                if (self.position.x > other_end.x or end.x < other.position.x) return false;
                if (self.position.y > other_end.y or end.y < other.position.y) return false;
            } else {
                if (self.position.x >= other_end.x or end.x <= other.position.x) return false;
                if (self.position.y >= other_end.y or end.y <= other.position.y) return false;
            }
            return true;
        }

        pub fn encloses(self: Self, other: Self) bool {
            const other_end = other.position.add(other.size);
            const end = self.position.add(self.size);
            return other.position.x >= self.position.x and other.position.y >= self.position.y and
                other_end.x <= end.x and other_end.y <= end.y;
        }

        pub fn intersection(self: Self, other: Self) Self {
            if (!self.intersects(other, false)) return .{};

            const position = V2{
                .x = @max(self.position.x, other.position.x),
                .y = @max(self.position.y, other.position.y),
            };
            const end = V2{
                .x = @min(self.position.x + self.size.x, other.position.x + other.size.x),
                .y = @min(self.position.y + self.size.y, other.position.y + other.size.y),
            };
            return .{ .position = position, .size = end.sub(position) };
        }

        pub fn merge(self: Self, other: Self) Self {
            const position = V2{
                .x = @min(self.position.x, other.position.x),
                .y = @min(self.position.y, other.position.y),
            };
            const end = V2{
                .x = @max(self.position.x + self.size.x, other.position.x + other.size.x),
                .y = @max(self.position.y + self.size.y, other.position.y + other.size.y),
            };
            return .{ .position = position, .size = end.sub(position) };
        }

        pub fn expand(self: Self, point: V2) Self {
            const begin = V2{
                .x = @min(self.position.x, point.x),
                .y = @min(self.position.y, point.y),
            };
            const end = V2{
                .x = @max(self.position.x + self.size.x, point.x),
                .y = @max(self.position.y + self.size.y, point.y),
            };
            return .{ .position = begin, .size = end.sub(begin) };
        }

        pub fn getSupport(self: Self, direction: V2) V2 {
            return .{
                .x = self.position.x + if (direction.x > 0) self.size.x else 0,
                .y = self.position.y + if (direction.y > 0) self.size.y else 0,
            };
        }

        pub fn grow(self: Self, amount: Real) Self {
            return .{
                .position = self.position.sub(V2{ .x = amount, .y = amount }),
                .size = self.size.add(V2{ .x = amount * 2, .y = amount * 2 }),
            };
        }

        pub fn growSide(self: Self, side: Side, amount: Real) Self {
            return self.growIndividual(
                if (side == .left) amount else 0,
                if (side == .top) amount else 0,
                if (side == .right) amount else 0,
                if (side == .bottom) amount else 0,
            );
        }

        pub fn growIndividual(self: Self, left: Real, top: Real, right: Real, bottom: Real) Self {
            return .{
                .position = .{
                    .x = self.position.x - left,
                    .y = self.position.y - top,
                },
                .size = .{
                    .x = self.size.x + left + right,
                    .y = self.size.y + top + bottom,
                },
            };
        }

        pub fn abs(self: Self) Self {
            return .{
                .position = self.position.add(self.size.minf(0)),
                .size = self.size.abs(),
            };
        }
    };
}

pub fn Rect2iOf(comptime T: type) type {
    const V2 = vector.Vector(T, 2);

    return extern struct {
        position: V2 = .zero,
        size: V2 = .zero,

        const Self = @This();

        pub inline fn toBinding(self: *const Self) bindings.builtins.Rect2i {
            return @as(*const bindings.builtins.Rect2i, @ptrCast(self)).*;
        }

        pub inline fn fromBinding(v: anytype) Self {
            const V = @TypeOf(v);
            return switch (V) {
                *bindings.builtins.Rect2i => @as(*const Self, @ptrCast(v)).*,
                *const bindings.builtins.Rect2i => @as(*const Self, @ptrCast(v)).*,
                bindings.builtins.Rect2i => @as(*const Self, @ptrCast(&v)).*,
                else => @compileError("Expected bindings.builtins.Rect2i by value or a pointer to it, found: " ++ @typeName(V)),
            };
        }

        pub inline fn bindingCall(
            self: *Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_rect2i_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2i_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2i_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallConst(
            self: *const Self,
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTupleSkipFirst(auto.FunctionOf(generated_rect2i_namespace.MemberFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2i_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2i_namespace, method);
            return @call(.auto, func, .{self} ++ args);
        }

        pub inline fn bindingCallStatic(
            comptime method: @EnumLiteral(),
            args: auto.FunctionArgsAsTuple(auto.FunctionOf(generated_rect2i_namespace.StaticFunctions, method)),
        ) auto.FunctionReturnType(auto.FunctionOf(generated_rect2i_namespace, method)) {
            const func = auto.FunctionOf(generated_rect2i_namespace, method);
            return @call(.auto, func, args);
        }

        pub fn init(position: V2, size: V2) Self {
            return .{ .position = position, .size = size };
        }

        pub fn getCenter(self: Self) V2 {
            return self.position.add(.{ .x = @divTrunc(self.size.x, 2), .y = @divTrunc(self.size.y, 2) });
        }

        pub fn getEnd(self: Self) V2 {
            return self.position.add(self.size);
        }

        pub fn setEnd(self: *Self, end: V2) void {
            self.size = end.sub(self.position);
        }

        pub fn getArea(self: Self) T {
            return self.size.x * self.size.y;
        }

        pub fn hasArea(self: Self) bool {
            return self.size.x > 0 and self.size.y > 0;
        }

        pub fn hasPoint(self: Self, point: V2) bool {
            if (point.x < self.position.x or point.y < self.position.y) return false;
            if (point.x >= self.position.x + self.size.x) return false;
            if (point.y >= self.position.y + self.size.y) return false;
            return true;
        }

        pub fn intersects(self: Self, other: Self) bool {
            const other_end = other.position.add(other.size);
            const end = self.position.add(self.size);
            if (self.position.x >= other_end.x or end.x <= other.position.x) return false;
            if (self.position.y >= other_end.y or end.y <= other.position.y) return false;
            return true;
        }

        pub fn encloses(self: Self, other: Self) bool {
            const other_end = other.position.add(other.size);
            const end = self.position.add(self.size);
            return other.position.x >= self.position.x and other.position.y >= self.position.y and
                other_end.x <= end.x and other_end.y <= end.y;
        }

        pub fn intersection(self: Self, other: Self) Self {
            if (!self.intersects(other)) return .{};

            const position = V2{
                .x = @max(self.position.x, other.position.x),
                .y = @max(self.position.y, other.position.y),
            };
            const end = V2{
                .x = @min(self.position.x + self.size.x, other.position.x + other.size.x),
                .y = @min(self.position.y + self.size.y, other.position.y + other.size.y),
            };
            return .{ .position = position, .size = end.sub(position) };
        }

        pub fn merge(self: Self, other: Self) Self {
            const position = V2{
                .x = @min(self.position.x, other.position.x),
                .y = @min(self.position.y, other.position.y),
            };
            const end = V2{
                .x = @max(self.position.x + self.size.x, other.position.x + other.size.x),
                .y = @max(self.position.y + self.size.y, other.position.y + other.size.y),
            };
            return .{ .position = position, .size = end.sub(position) };
        }

        pub fn expand(self: Self, point: V2) Self {
            const begin = V2{
                .x = @min(self.position.x, point.x),
                .y = @min(self.position.y, point.y),
            };
            const end = V2{
                .x = @max(self.position.x + self.size.x, point.x),
                .y = @max(self.position.y + self.size.y, point.y),
            };
            return .{ .position = begin, .size = end.sub(begin) };
        }

        pub fn getSupport(self: Self, direction: V2) V2 {
            return .{
                .x = self.position.x + if (direction.x > 0) self.size.x else 0,
                .y = self.position.y + if (direction.y > 0) self.size.y else 0,
            };
        }

        pub fn grow(self: Self, amount: T) Self {
            return .{
                .position = self.position.sub(.{ .x = amount, .y = amount }),
                .size = self.size.add(.{ .x = amount * 2, .y = amount * 2 }),
            };
        }

        pub fn growSide(self: Self, side: Side, amount: T) Self {
            return self.growIndividual(
                if (side == .left) amount else 0,
                if (side == .top) amount else 0,
                if (side == .right) amount else 0,
                if (side == .bottom) amount else 0,
            );
        }

        pub fn growIndividual(self: Self, left: T, top: T, right: T, bottom: T) Self {
            return .{
                .position = .{
                    .x = self.position.x - left,
                    .y = self.position.y - top,
                },
                .size = .{
                    .x = self.size.x + left + right,
                    .y = self.size.y + top + bottom,
                },
            };
        }

        pub fn abs(self: Self) Self {
            return .{
                .position = self.position.add(self.size.mini(0)),
                .size = self.size.abs(),
            };
        }
    };
}

const IntRect2 = Rect2iOf(i32);

pub const single = struct {
    pub const Rect2 = Rect2Of(f32);
    pub const Rect2i = IntRect2;
};

pub const double = struct {
    pub const Rect2 = Rect2Of(f64);
    pub const Rect2i = IntRect2;
};

const precision = if (bindings.is_double_precision) double else single;
pub const Rect2 = precision.Rect2;
pub const Rect2i = IntRect2;

test "Rect2 end member" {
    const R = single.Rect2;
    var rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(vector.single.Vector2{ .x = 5, .y = 8 }, rect.getEnd());
    rect.setEnd(.{ .x = 10, .y = 12 });
    try std.testing.expectEqual(vector.single.Vector2{ .x = 9, .y = 10 }, rect.size);
}

test "Rect2i end member" {
    const R = Rect2i;
    var rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(vector.single.Vector2i{ .x = 5, .y = 8 }, rect.getEnd());
    rect.setEnd(.{ .x = 10, .y = 12 });
    try std.testing.expectEqual(vector.single.Vector2i{ .x = 9, .y = 10 }, rect.size);
}

test "Rect2 layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(single.Rect2));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(double.Rect2));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Rect2i));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(single.Rect2));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(double.Rect2));
}

test "Rect2 basics" {
    const R = single.Rect2;
    const V = vector.single.Vector2;

    const rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(V{ .x = 3, .y = 5 }, rect.getCenter());
    try std.testing.expectEqual(@as(f32, 24), rect.getArea());
    try std.testing.expect(rect.hasArea());
    try std.testing.expect(rect.hasPoint(.{ .x = 1, .y = 2 }));
    try std.testing.expect(!rect.hasPoint(.{ .x = 5, .y = 2 }));
    try std.testing.expect(rect.isFinite());

    const border = R.init(.{ .x = 5, .y = 2 }, .{ .x = 2, .y = 2 });
    try std.testing.expect(!rect.intersects(border, false));
    try std.testing.expect(rect.intersects(border, true));

    try std.testing.expect(rect.encloses(R.init(.{ .x = 2, .y = 3 }, .{ .x = 1, .y = 1 })));
    try std.testing.expect(!rect.encloses(border));

    const overlap = R.init(.{ .x = 3, .y = 4 }, .{ .x = 4, .y = 4 });
    const intersection = rect.intersection(overlap);
    try std.testing.expectEqual(V{ .x = 3, .y = 4 }, intersection.position);
    try std.testing.expectEqual(V{ .x = 2, .y = 4 }, intersection.size);
    try std.testing.expectEqual(R{}, rect.intersection(border));

    const merged = rect.merge(border);
    try std.testing.expectEqual(V{ .x = 1, .y = 2 }, merged.position);
    try std.testing.expectEqual(V{ .x = 6, .y = 6 }, merged.size);

    try std.testing.expectEqual(V{ .x = 5, .y = 8 }, rect.getSupport(.{ .x = 1, .y = 1 }));
    try std.testing.expectEqual(V{ .x = 1, .y = 2 }, rect.getSupport(.{ .x = -1, .y = -1 }));
}

test "Rect2 growth and abs" {
    const R = single.Rect2;
    const V = vector.single.Vector2;

    const rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });

    const grown = rect.grow(1);
    try std.testing.expectEqual(V{ .x = 0, .y = 1 }, grown.position);
    try std.testing.expectEqual(V{ .x = 6, .y = 8 }, grown.size);

    const side = rect.growSide(.left, 1);
    try std.testing.expectEqual(V{ .x = 0, .y = 2 }, side.position);
    try std.testing.expectEqual(V{ .x = 5, .y = 6 }, side.size);

    const individual = rect.growIndividual(1, 2, 3, 4);
    try std.testing.expectEqual(V{ .x = 0, .y = 0 }, individual.position);
    try std.testing.expectEqual(V{ .x = 8, .y = 12 }, individual.size);

    const negative = R.init(.{ .x = 10, .y = 10 }, .{ .x = -4, .y = -6 });
    const positive = negative.abs();
    try std.testing.expectEqual(V{ .x = 6, .y = 4 }, positive.position);
    try std.testing.expectEqual(V{ .x = 4, .y = 6 }, positive.size);

    const expanded = rect.expand(.{ .x = 0, .y = 10 });
    try std.testing.expectEqual(V{ .x = 0, .y = 2 }, expanded.position);
    try std.testing.expectEqual(V{ .x = 5, .y = 8 }, expanded.size);
}

test "Rect2i basics" {
    const R = Rect2i;
    const V = vector.single.Vector2i;

    const rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(V{ .x = 3, .y = 5 }, rect.getCenter());
    try std.testing.expectEqual(@as(i32, 24), rect.getArea());
    try std.testing.expect(rect.hasPoint(.{ .x = 1, .y = 2 }));
    try std.testing.expect(!rect.hasPoint(.{ .x = 5, .y = 2 }));

    const other = R.init(.{ .x = 3, .y = 4 }, .{ .x = 4, .y = 4 });
    const intersection = rect.intersection(other);
    try std.testing.expectEqual(V{ .x = 3, .y = 4 }, intersection.position);
    try std.testing.expectEqual(V{ .x = 2, .y = 4 }, intersection.size);

    const merged = rect.merge(other);
    try std.testing.expectEqual(V{ .x = 1, .y = 2 }, merged.position);
    try std.testing.expectEqual(V{ .x = 6, .y = 6 }, merged.size);

    try std.testing.expectEqual(V{ .x = 7, .y = 8 }, rect.expand(.{ .x = 7, .y = 8 }).size.add(rect.position));
    try std.testing.expectEqual(V{ .x = 0, .y = 1 }, rect.grow(1).position);

    const negative = R.init(.{ .x = 10, .y = 10 }, .{ .x = -4, .y = -6 });
    const positive = negative.abs();
    try std.testing.expectEqual(V{ .x = 6, .y = 4 }, positive.position);
    try std.testing.expectEqual(V{ .x = 4, .y = 6 }, positive.size);
}

test "Rect2 double precision" {
    const R = double.Rect2;
    const rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(@as(f64, 24), rect.getArea());
    try std.testing.expectEqual(vector.double.Vector2{ .x = 3, .y = 5 }, rect.getCenter());
}

const std = @import("std");
const bindings = @import("bindings");
const auto = @import("../auto/auto.zig");
const generated_rect2_namespace = @import("generated/rect2.zig");
const generated_rect2i_namespace = @import("generated/rect2i.zig");
const vector = @import("vector.zig");
