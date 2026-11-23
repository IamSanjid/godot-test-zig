//! Tests for the pure-Zig `Rect2` and `Rect2i` builtins.

test "Rect2 end member" {
    const R = rect_mod.single.Rect2;
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
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(rect_mod.single.Rect2));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(rect_mod.double.Rect2));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Rect2i));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(rect_mod.single.Rect2));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(rect_mod.double.Rect2));
}

test "Rect2 basics" {
    const R = rect_mod.single.Rect2;
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
    const R = rect_mod.single.Rect2;
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
    const R = rect_mod.double.Rect2;
    const rect = R.init(.{ .x = 1, .y = 2 }, .{ .x = 4, .y = 6 });
    try std.testing.expectEqual(@as(f64, 24), rect.getArea());
    try std.testing.expectEqual(vector.double.Vector2{ .x = 3, .y = 5 }, rect.getCenter());
}

const std = @import("std");

const godot = @import("godot");
const Rect2i = godot.builtins.Rect2i;
const rect_mod = godot.builtins.rect;
const vector = godot.builtins.vector;
