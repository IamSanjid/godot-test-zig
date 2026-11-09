//! Port of Godot's bundled `ok_color.h` subset used by `Color` OKHSL
//! conversion. Only the OKHSL ↔ sRGB paths are implemented.
//!
//! Original algorithm: Björn Ottosson, public domain / MIT-style header.

pub const Rgb = struct {
    r: f32,
    g: f32,
    b: f32,
};

pub const Hsl = struct {
    h: f32,
    s: f32,
    l: f32,
};

const Lab = struct {
    l: f32,
    a: f32,
    b: f32,
};

const Lc = struct {
    l: f32,
    c: f32,
};

const St = struct {
    s: f32,
    t: f32,
};

const Cs = struct {
    c_0: f32,
    c_mid: f32,
    c_max: f32,
};

pub fn okhslToSrgb(hsl: Hsl) Rgb {
    if (hsl.l == 1) return .{ .r = 1, .g = 1, .b = 1 };
    if (hsl.l == 0) return .{ .r = 0, .g = 0, .b = 0 };

    const a_ = @cos(2 * std.math.pi * hsl.h);
    const b_ = @sin(2 * std.math.pi * hsl.h);
    const l = toeInv(hsl.l);

    const cs = getCs(l, a_, b_);
    const c_0 = cs.c_0;
    const c_mid = cs.c_mid;
    const c_max = cs.c_max;

    const mid: f32 = 0.8;
    const mid_inv: f32 = 1.25;

    var c: f32 = undefined;
    if (hsl.s < mid) {
        const t = mid_inv * hsl.s;
        const k_1 = mid * c_0;
        const k_2 = 1 - k_1 / c_mid;
        c = t * k_1 / (1 - k_2 * t);
    } else {
        const t = (hsl.s - mid) / (1 - mid);
        const k_0 = c_mid;
        const k_1 = (1 - mid) * c_mid * c_mid * mid_inv * mid_inv / c_0;
        const k_2 = 1 - k_1 / (c_max - c_mid);
        c = k_0 + t * k_1 / (1 - k_2 * t);
    }

    const rgb = oklabToLinearSrgb(.{ .l = l, .a = c * a_, .b = c * b_ });
    return .{
        .r = srgbTransferFunction(rgb.r),
        .g = srgbTransferFunction(rgb.g),
        .b = srgbTransferFunction(rgb.b),
    };
}

pub fn srgbToOkhsl(rgb: Rgb) Hsl {
    if (rgb.r == 0 and rgb.g == 0 and rgb.b == 0) {
        return .{ .h = 0, .s = 0, .l = 0 };
    }

    const lab = linearSrgbToOklab(.{
        .r = srgbTransferFunctionInv(rgb.r),
        .g = srgbTransferFunctionInv(rgb.g),
        .b = srgbTransferFunctionInv(rgb.b),
    });

    const c = @sqrt(lab.a * lab.a + lab.b * lab.b);
    const a_ = lab.a / c;
    const b_ = lab.b / c;
    const l = lab.l;
    const h = 0.5 + 0.5 * std.math.atan2(-lab.b, -lab.a) / std.math.pi;

    const cs = getCs(l, a_, b_);
    const c_0 = cs.c_0;
    const c_mid = cs.c_mid;
    const c_max = cs.c_max;

    const mid: f32 = 0.8;
    const mid_inv: f32 = 1.25;

    var s: f32 = undefined;
    if (c < c_mid) {
        const k_1 = mid * c_0;
        const k_2 = 1 - k_1 / c_mid;
        const t = c / (k_1 + k_2 * c);
        s = t * mid;
    } else {
        const k_0 = c_mid;
        const k_1 = (1 - mid) * c_mid * c_mid * mid_inv * mid_inv / c_0;
        const k_2 = 1 - k_1 / (c_max - c_mid);
        const t = (c - k_0) / (k_1 + k_2 * (c - k_0));
        s = mid + (1 - mid) * t;
    }

    return .{ .h = h, .s = s, .l = toe(l) };
}

fn srgbTransferFunction(a: f32) f32 {
    return if (0.0031308 >= a)
        12.92 * a
    else
        1.055 * std.math.pow(f32, a, 0.4166666666666667) - 0.055;
}

fn srgbTransferFunctionInv(a: f32) f32 {
    return if (0.04045 < a)
        std.math.pow(f32, (a + 0.055) / 1.055, 2.4)
    else
        a / 12.92;
}

fn linearSrgbToOklab(c: Rgb) Lab {
    const l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    const m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    const s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;

    const l_ = std.math.cbrt(l);
    const m_ = std.math.cbrt(m);
    const s_ = std.math.cbrt(s);

    return .{
        .l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        .a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        .b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    };
}

fn oklabToLinearSrgb(c: Lab) Rgb {
    const l_ = c.l + 0.3963377774 * c.a + 0.2158037573 * c.b;
    const m_ = c.l - 0.1055613458 * c.a - 0.0638541728 * c.b;
    const s_ = c.l - 0.0894841775 * c.a - 1.2914855480 * c.b;

    const l = l_ * l_ * l_;
    const m = m_ * m_ * m_;
    const s = s_ * s_ * s_;

    return .{
        .r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        .g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        .b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    };
}

fn computeMaxSaturation(a: f32, b: f32) f32 {
    var k0: f32 = undefined;
    var k1: f32 = undefined;
    var k2: f32 = undefined;
    var k3: f32 = undefined;
    var k4: f32 = undefined;
    var wl: f32 = undefined;
    var wm: f32 = undefined;
    var ws: f32 = undefined;

    if (-1.88170328 * a - 0.80936493 * b > 1) {
        k0 = 1.19086277;
        k1 = 1.76576728;
        k2 = 0.59662641;
        k3 = 0.75515197;
        k4 = 0.56771245;
        wl = 4.0767416621;
        wm = -3.3077115913;
        ws = 0.2309699292;
    } else if (1.81444104 * a - 1.19445276 * b > 1) {
        k0 = 0.73956515;
        k1 = -0.45954404;
        k2 = 0.08285427;
        k3 = 0.12541070;
        k4 = 0.14503204;
        wl = -1.2684380046;
        wm = 2.6097574011;
        ws = -0.3413193965;
    } else {
        k0 = 1.35733652;
        k1 = -0.00915799;
        k2 = -1.15130210;
        k3 = -0.50559606;
        k4 = 0.00692167;
        wl = -0.0041960863;
        wm = -0.7034186147;
        ws = 1.7076147010;
    }

    var s = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b;

    const k_l = 0.3963377774 * a + 0.2158037573 * b;
    const k_m = -0.1055613458 * a - 0.0638541728 * b;
    const k_s = -0.0894841775 * a - 1.2914855480 * b;

    const l_ = 1 + s * k_l;
    const m_ = 1 + s * k_m;
    const s_ = 1 + s * k_s;

    const l = l_ * l_ * l_;
    const m = m_ * m_ * m_;
    const s3 = s_ * s_ * s_;

    const l_ds = 3 * k_l * l_ * l_;
    const m_ds = 3 * k_m * m_ * m_;
    const s_ds = 3 * k_s * s_ * s_;

    const l_ds2 = 6 * k_l * k_l * l_;
    const m_ds2 = 6 * k_m * k_m * m_;
    const s_ds2 = 6 * k_s * k_s * s_;

    const f = wl * l + wm * m + ws * s3;
    const f1 = wl * l_ds + wm * m_ds + ws * s_ds;
    const f2 = wl * l_ds2 + wm * m_ds2 + ws * s_ds2;

    s = s - f * f1 / (f1 * f1 - 0.5 * f * f2);
    return s;
}

fn findCusp(a: f32, b: f32) Lc {
    const s_cusp = computeMaxSaturation(a, b);
    const rgb_at_max = oklabToLinearSrgb(.{ .l = 1, .a = s_cusp * a, .b = s_cusp * b });
    const l_cusp = std.math.cbrt(1 / @max(@max(rgb_at_max.r, rgb_at_max.g), rgb_at_max.b));
    return .{ .l = l_cusp, .c = l_cusp * s_cusp };
}

fn findGamutIntersection(a: f32, b: f32, l1: f32, c1: f32, l0: f32, cusp: Lc) f32 {
    var t: f32 = undefined;
    if (((l1 - l0) * cusp.c - (cusp.l - l0) * c1) <= 0) {
        t = cusp.c * l0 / (c1 * cusp.l + cusp.c * (l0 - l1));
    } else {
        t = cusp.c * (l0 - 1) / (c1 * (cusp.l - 1) + cusp.c * (l0 - l1));

        const dl = l1 - l0;
        const dc = c1;

        const k_l = 0.3963377774 * a + 0.2158037573 * b;
        const k_m = -0.1055613458 * a - 0.0638541728 * b;
        const k_s = -0.0894841775 * a - 1.2914855480 * b;

        const l_dt = dl + dc * k_l;
        const m_dt = dl + dc * k_m;
        const s_dt = dl + dc * k_s;

        const l = l0 * (1 - t) + t * l1;
        const c = t * c1;

        const l_ = l + c * k_l;
        const m_ = l + c * k_m;
        const s_ = l + c * k_s;

        const l3 = l_ * l_ * l_;
        const m3 = m_ * m_ * m_;
        const s3 = s_ * s_ * s_;

        const ldt = 3 * l_dt * l_ * l_;
        const mdt = 3 * m_dt * m_ * m_;
        const sdt = 3 * s_dt * s_ * s_;

        const ldt2 = 6 * l_dt * l_dt * l_;
        const mdt2 = 6 * m_dt * m_dt * m_;
        const sdt2 = 6 * s_dt * s_dt * s_;

        const r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3 - 1;
        const r1 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
        const r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;

        const u_r = r1 / (r1 * r1 - 0.5 * r * r2);
        var t_r = -r * u_r;

        const g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3 - 1;
        const g1 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
        const g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;

        const u_g = g1 / (g1 * g1 - 0.5 * g * g2);
        var t_g = -g * u_g;

        const b_component = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3 - 1;
        const b1 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.7076147010 * sdt;
        const b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2;

        const u_b = b1 / (b1 * b1 - 0.5 * b_component * b2);
        var t_b = -b_component * u_b;

        const max_float = std.math.floatMax(f32);
        t_r = if (u_r >= 0) t_r else max_float;
        t_g = if (u_g >= 0) t_g else max_float;
        t_b = if (u_b >= 0) t_b else max_float;

        t += @min(t_r, @min(t_g, t_b));
    }

    return t;
}

fn toSt(cusp: Lc) St {
    return .{ .s = cusp.c / cusp.l, .t = cusp.c / (1 - cusp.l) };
}

fn getStMid(a: f32, b: f32) St {
    const s = 0.11516993 + 1 / (7.44778970 + 4.15901240 * b +
        a * (-2.19557347 + 1.75198401 * b +
            a * (-2.13704948 - 10.02301043 * b +
                a * (-4.24894561 + 5.38770819 * b + 4.69891013 * a))));

    const t = 0.11239642 + 1 / (1.61320320 - 0.68124379 * b +
        a * (0.40370612 + 0.90148123 * b +
            a * (-0.27087943 + 0.61223990 * b +
                a * (0.00299215 - 0.45399568 * b - 0.14661872 * a))));

    return .{ .s = s, .t = t };
}

fn getCs(l: f32, a: f32, b: f32) Cs {
    const cusp = findCusp(a, b);
    const c_max = findGamutIntersection(a, b, l, 1, l, cusp);
    const st_max = toSt(cusp);

    const k = c_max / @min(l * st_max.s, (1 - l) * st_max.t);
    const st_mid = getStMid(a, b);

    const c_a = l * st_mid.s;
    const c_b = (1 - l) * st_mid.t;
    const c_mid = 0.9 * k * @sqrt(@sqrt(1 / (1 / (c_a * c_a * c_a * c_a) + 1 / (c_b * c_b * c_b * c_b))));

    const c_a0 = l * 0.4;
    const c_b0 = (1 - l) * 0.8;
    const c_0 = @sqrt(1 / (1 / (c_a0 * c_a0) + 1 / (c_b0 * c_b0)));

    return .{ .c_0 = c_0, .c_mid = c_mid, .c_max = c_max };
}

fn toe(x: f32) f32 {
    const k_1: f32 = 0.206;
    const k_2: f32 = 0.03;
    const k_3 = (1 + k_1) / (1 + k_2);
    return 0.5 * (k_3 * x - k_1 + @sqrt((k_3 * x - k_1) * (k_3 * x - k_1) + 4 * k_2 * k_3 * x));
}

fn toeInv(x: f32) f32 {
    const k_1: f32 = 0.206;
    const k_2: f32 = 0.03;
    const k_3 = (1 + k_1) / (1 + k_2);
    return (x * x + k_1 * x) / (k_3 * (x + k_2));
}

test "okhsl grayscale and round-trip" {
    const gray = okhslToSrgb(.{ .h = 0.5, .s = 0, .l = 0.5 });
    try std.testing.expectApproxEqAbs(gray.r, gray.g, 0.00001);
    try std.testing.expectApproxEqAbs(gray.g, gray.b, 0.00001);

    const source = Rgb{ .r = 0.2, .g = 0.5, .b = 0.8 };
    const hsl = srgbToOkhsl(source);
    const round_trip = okhslToSrgb(hsl);
    try std.testing.expectApproxEqAbs(source.r, round_trip.r, 0.0001);
    try std.testing.expectApproxEqAbs(source.g, round_trip.g, 0.0001);
    try std.testing.expectApproxEqAbs(source.b, round_trip.b, 0.0001);
}

const std = @import("std");
