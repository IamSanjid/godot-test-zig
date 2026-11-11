//! Shared numeric constants for the pure-Zig builtins.
//!
//! Values follow Godot's `core/math/math_defs.h`. The `double` namespace keeps
//! separate entries where a tighter tolerance is useful for f64 math; the
//! top-level names are the single-precision defaults for now.

pub const single = struct {
    /// `CMP_EPSILON`: general approximate-comparison tolerance.
    pub const cmp_epsilon = 0.00001;
    pub const cmp_epsilon_squared = single.cmp_epsilon * single.cmp_epsilon;
    /// `UNIT_EPSILON`: tolerance for unit-length values such as normals.
    pub const unit_epsilon = 0.001;
    /// `CMP_NORMALIZE_TOLERANCE`.
    pub const normalize_tolerance = 0.000001;
    /// `CMP_POINT_IN_PLANE_EPSILON`.
    pub const point_in_plane_epsilon = 0.00001;
    /// Godot's Euler-decomposition epsilon (`Basis::get_euler`).
    pub const euler_epsilon = 0.00000025;
    /// Small denominator guard used by ray/segment slab tests.
    pub const ray_epsilon = 1e-10;
    /// Color byte/word quantization maxima.
    pub const color_byte_max = 255.0;
    pub const color_word_max = 65535.0;
};

pub const double = struct {
    pub const cmp_epsilon = 0.00001;
    pub const cmp_epsilon_squared = double.cmp_epsilon * double.cmp_epsilon;
    /// Double math can use the precise-math-checks unit tolerance.
    pub const unit_epsilon = 0.00001;
    pub const normalize_tolerance = 0.000001;
    pub const point_in_plane_epsilon = 0.00001;
    pub const euler_epsilon = 0.00000025;
    pub const ray_epsilon = 1e-10;
    pub const color_byte_max = 255.0;
    pub const color_word_max = 65535.0;
};

/// Selects the constants that match a real scalar type.
pub fn For(comptime Real: type) type {
    return if (Real == f64) double else single;
}

const precision = if (@import("bindings").is_double_precision) double else single;
pub const cmp_epsilon = precision.cmp_epsilon;
pub const cmp_epsilon_squared = precision.cmp_epsilon_squared;
pub const unit_epsilon = precision.unit_epsilon;
pub const normalize_tolerance = precision.normalize_tolerance;
pub const point_in_plane_epsilon = precision.point_in_plane_epsilon;
pub const euler_epsilon = precision.euler_epsilon;
pub const ray_epsilon = precision.ray_epsilon;
pub const color_byte_max = precision.color_byte_max;
pub const color_word_max = precision.color_word_max;

test "precision-selected constants" {
    try std.testing.expectEqual(@as(f64, 0.001), single.unit_epsilon);
    try std.testing.expectEqual(@as(f64, 0.00001), double.unit_epsilon);
    try std.testing.expectEqual(single, For(f32));
    try std.testing.expectEqual(double, For(f64));
}

const std = @import("std");
