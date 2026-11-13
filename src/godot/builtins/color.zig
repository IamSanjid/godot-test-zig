//! Pure-Zig implementation of Godot's `Color` builtin.
//!
//! Godot stores `Color` as four `float`s even in double builds, so this file
//! defines the struct directly (no `single`/`double` split).
//! String-based helpers (`to_html`, `html`, `html_is_valid`, `from_string`) are
//! deferred until the `String` builtin exists. The `r8`/`hsv`/`ok_hsl` members
//! are computed and exposed through Godot-style getter/setter pairs.

pub const Color = extern struct {
    pub const GodotClassName = "Color";

    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 1,

    const Self = @This();
    const C = constants.single;

    pub inline fn toBinding(self: *const Self) bindings.builtins.Color {
        return @as(*const bindings.builtins.Color, @ptrCast(self)).*;
    }

    pub inline fn fromBinding(v: anytype) Self {
        const V = @TypeOf(v);
        return switch (V) {
            *bindings.builtins.Color => @as(*const Self, @ptrCast(v)).*,
            *const bindings.builtins.Color => @as(*const Self, @ptrCast(v)).*,
            bindings.builtins.Color => @as(*const Self, @ptrCast(&v)).*,
            else => @compileError("Expected bindings.builtins.Color by value or a pointer to it, found: " ++ @typeName(V)),
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

    pub fn init(r: f32, g: f32, b: f32, a: f32) Self {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub const alice_blue: Self = .{ .r = 0.9411765, .g = 0.972549, .b = 1, .a = 1 };
    pub const antique_white: Self = .{ .r = 0.98039216, .g = 0.92156863, .b = 0.84313726, .a = 1 };
    pub const aqua: Self = .{ .r = 0, .g = 1, .b = 1, .a = 1 };
    pub const aquamarine: Self = .{ .r = 0.49803922, .g = 1, .b = 0.83137256, .a = 1 };
    pub const azure: Self = .{ .r = 0.9411765, .g = 1, .b = 1, .a = 1 };
    pub const beige: Self = .{ .r = 0.9607843, .g = 0.9607843, .b = 0.8627451, .a = 1 };
    pub const bisque: Self = .{ .r = 1, .g = 0.89411765, .b = 0.76862746, .a = 1 };
    pub const black: Self = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const blanched_almond: Self = .{ .r = 1, .g = 0.92156863, .b = 0.8039216, .a = 1 };
    pub const blue: Self = .{ .r = 0, .g = 0, .b = 1, .a = 1 };
    pub const blue_violet: Self = .{ .r = 0.5411765, .g = 0.16862746, .b = 0.8862745, .a = 1 };
    pub const brown: Self = .{ .r = 0.64705884, .g = 0.16470589, .b = 0.16470589, .a = 1 };
    pub const burlywood: Self = .{ .r = 0.87058824, .g = 0.72156864, .b = 0.5294118, .a = 1 };
    pub const cadet_blue: Self = .{ .r = 0.37254903, .g = 0.61960787, .b = 0.627451, .a = 1 };
    pub const chartreuse: Self = .{ .r = 0.49803922, .g = 1, .b = 0, .a = 1 };
    pub const chocolate: Self = .{ .r = 0.8235294, .g = 0.4117647, .b = 0.11764706, .a = 1 };
    pub const coral: Self = .{ .r = 1, .g = 0.49803922, .b = 0.3137255, .a = 1 };
    pub const cornflower_blue: Self = .{ .r = 0.39215687, .g = 0.58431375, .b = 0.92941177, .a = 1 };
    pub const cornsilk: Self = .{ .r = 1, .g = 0.972549, .b = 0.8627451, .a = 1 };
    pub const crimson: Self = .{ .r = 0.8627451, .g = 0.078431375, .b = 0.23529412, .a = 1 };
    pub const cyan: Self = .{ .r = 0, .g = 1, .b = 1, .a = 1 };
    pub const dark_blue: Self = .{ .r = 0, .g = 0, .b = 0.54509807, .a = 1 };
    pub const dark_cyan: Self = .{ .r = 0, .g = 0.54509807, .b = 0.54509807, .a = 1 };
    pub const dark_goldenrod: Self = .{ .r = 0.72156864, .g = 0.5254902, .b = 0.043137256, .a = 1 };
    pub const dark_gray: Self = .{ .r = 0.6627451, .g = 0.6627451, .b = 0.6627451, .a = 1 };
    pub const dark_green: Self = .{ .r = 0, .g = 0.39215687, .b = 0, .a = 1 };
    pub const dark_khaki: Self = .{ .r = 0.7411765, .g = 0.7176471, .b = 0.41960785, .a = 1 };
    pub const dark_magenta: Self = .{ .r = 0.54509807, .g = 0, .b = 0.54509807, .a = 1 };
    pub const dark_olive_green: Self = .{ .r = 0.33333334, .g = 0.41960785, .b = 0.18431373, .a = 1 };
    pub const dark_orange: Self = .{ .r = 1, .g = 0.54901963, .b = 0, .a = 1 };
    pub const dark_orchid: Self = .{ .r = 0.6, .g = 0.19607843, .b = 0.8, .a = 1 };
    pub const dark_red: Self = .{ .r = 0.54509807, .g = 0, .b = 0, .a = 1 };
    pub const dark_salmon: Self = .{ .r = 0.9137255, .g = 0.5882353, .b = 0.47843137, .a = 1 };
    pub const dark_sea_green: Self = .{ .r = 0.56078434, .g = 0.7372549, .b = 0.56078434, .a = 1 };
    pub const dark_slate_blue: Self = .{ .r = 0.28235295, .g = 0.23921569, .b = 0.54509807, .a = 1 };
    pub const dark_slate_gray: Self = .{ .r = 0.18431373, .g = 0.30980393, .b = 0.30980393, .a = 1 };
    pub const dark_turquoise: Self = .{ .r = 0, .g = 0.80784315, .b = 0.81960785, .a = 1 };
    pub const dark_violet: Self = .{ .r = 0.5803922, .g = 0, .b = 0.827451, .a = 1 };
    pub const deep_pink: Self = .{ .r = 1, .g = 0.078431375, .b = 0.5764706, .a = 1 };
    pub const deep_sky_blue: Self = .{ .r = 0, .g = 0.7490196, .b = 1, .a = 1 };
    pub const dim_gray: Self = .{ .r = 0.4117647, .g = 0.4117647, .b = 0.4117647, .a = 1 };
    pub const dodger_blue: Self = .{ .r = 0.11764706, .g = 0.5647059, .b = 1, .a = 1 };
    pub const firebrick: Self = .{ .r = 0.69803923, .g = 0.13333334, .b = 0.13333334, .a = 1 };
    pub const floral_white: Self = .{ .r = 1, .g = 0.98039216, .b = 0.9411765, .a = 1 };
    pub const forest_green: Self = .{ .r = 0.13333334, .g = 0.54509807, .b = 0.13333334, .a = 1 };
    pub const fuchsia: Self = .{ .r = 1, .g = 0, .b = 1, .a = 1 };
    pub const gainsboro: Self = .{ .r = 0.8627451, .g = 0.8627451, .b = 0.8627451, .a = 1 };
    pub const ghost_white: Self = .{ .r = 0.972549, .g = 0.972549, .b = 1, .a = 1 };
    pub const gold: Self = .{ .r = 1, .g = 0.84313726, .b = 0, .a = 1 };
    pub const goldenrod: Self = .{ .r = 0.85490197, .g = 0.64705884, .b = 0.1254902, .a = 1 };
    pub const gray: Self = .{ .r = 0.74509805, .g = 0.74509805, .b = 0.74509805, .a = 1 };
    pub const green: Self = .{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const green_yellow: Self = .{ .r = 0.6784314, .g = 1, .b = 0.18431373, .a = 1 };
    pub const honeydew: Self = .{ .r = 0.9411765, .g = 1, .b = 0.9411765, .a = 1 };
    pub const hot_pink: Self = .{ .r = 1, .g = 0.4117647, .b = 0.7058824, .a = 1 };
    pub const indian_red: Self = .{ .r = 0.8039216, .g = 0.36078432, .b = 0.36078432, .a = 1 };
    pub const indigo: Self = .{ .r = 0.29411766, .g = 0, .b = 0.50980395, .a = 1 };
    pub const ivory: Self = .{ .r = 1, .g = 1, .b = 0.9411765, .a = 1 };
    pub const khaki: Self = .{ .r = 0.9411765, .g = 0.9019608, .b = 0.54901963, .a = 1 };
    pub const lavender: Self = .{ .r = 0.9019608, .g = 0.9019608, .b = 0.98039216, .a = 1 };
    pub const lavender_blush: Self = .{ .r = 1, .g = 0.9411765, .b = 0.9607843, .a = 1 };
    pub const lawn_green: Self = .{ .r = 0.4862745, .g = 0.9882353, .b = 0, .a = 1 };
    pub const lemon_chiffon: Self = .{ .r = 1, .g = 0.98039216, .b = 0.8039216, .a = 1 };
    pub const light_blue: Self = .{ .r = 0.6784314, .g = 0.84705883, .b = 0.9019608, .a = 1 };
    pub const light_coral: Self = .{ .r = 0.9411765, .g = 0.5019608, .b = 0.5019608, .a = 1 };
    pub const light_cyan: Self = .{ .r = 0.8784314, .g = 1, .b = 1, .a = 1 };
    pub const light_goldenrod: Self = .{ .r = 0.98039216, .g = 0.98039216, .b = 0.8235294, .a = 1 };
    pub const light_gray: Self = .{ .r = 0.827451, .g = 0.827451, .b = 0.827451, .a = 1 };
    pub const light_green: Self = .{ .r = 0.5647059, .g = 0.93333334, .b = 0.5647059, .a = 1 };
    pub const light_pink: Self = .{ .r = 1, .g = 0.7137255, .b = 0.75686276, .a = 1 };
    pub const light_salmon: Self = .{ .r = 1, .g = 0.627451, .b = 0.47843137, .a = 1 };
    pub const light_sea_green: Self = .{ .r = 0.1254902, .g = 0.69803923, .b = 0.6666667, .a = 1 };
    pub const light_sky_blue: Self = .{ .r = 0.5294118, .g = 0.80784315, .b = 0.98039216, .a = 1 };
    pub const light_slate_gray: Self = .{ .r = 0.46666667, .g = 0.53333336, .b = 0.6, .a = 1 };
    pub const light_steel_blue: Self = .{ .r = 0.6901961, .g = 0.76862746, .b = 0.87058824, .a = 1 };
    pub const light_yellow: Self = .{ .r = 1, .g = 1, .b = 0.8784314, .a = 1 };
    pub const lime: Self = .{ .r = 0, .g = 1, .b = 0, .a = 1 };
    pub const lime_green: Self = .{ .r = 0.19607843, .g = 0.8039216, .b = 0.19607843, .a = 1 };
    pub const linen: Self = .{ .r = 0.98039216, .g = 0.9411765, .b = 0.9019608, .a = 1 };
    pub const magenta: Self = .{ .r = 1, .g = 0, .b = 1, .a = 1 };
    pub const maroon: Self = .{ .r = 0.6901961, .g = 0.1882353, .b = 0.3764706, .a = 1 };
    pub const medium_aquamarine: Self = .{ .r = 0.4, .g = 0.8039216, .b = 0.6666667, .a = 1 };
    pub const medium_blue: Self = .{ .r = 0, .g = 0, .b = 0.8039216, .a = 1 };
    pub const medium_orchid: Self = .{ .r = 0.7294118, .g = 0.33333334, .b = 0.827451, .a = 1 };
    pub const medium_purple: Self = .{ .r = 0.5764706, .g = 0.4392157, .b = 0.85882354, .a = 1 };
    pub const medium_sea_green: Self = .{ .r = 0.23529412, .g = 0.7019608, .b = 0.44313726, .a = 1 };
    pub const medium_slate_blue: Self = .{ .r = 0.48235294, .g = 0.40784314, .b = 0.93333334, .a = 1 };
    pub const medium_spring_green: Self = .{ .r = 0, .g = 0.98039216, .b = 0.6039216, .a = 1 };
    pub const medium_turquoise: Self = .{ .r = 0.28235295, .g = 0.81960785, .b = 0.8, .a = 1 };
    pub const medium_violet_red: Self = .{ .r = 0.78039217, .g = 0.08235294, .b = 0.52156866, .a = 1 };
    pub const midnight_blue: Self = .{ .r = 0.09803922, .g = 0.09803922, .b = 0.4392157, .a = 1 };
    pub const mint_cream: Self = .{ .r = 0.9607843, .g = 1, .b = 0.98039216, .a = 1 };
    pub const misty_rose: Self = .{ .r = 1, .g = 0.89411765, .b = 0.88235295, .a = 1 };
    pub const moccasin: Self = .{ .r = 1, .g = 0.89411765, .b = 0.70980394, .a = 1 };
    pub const navajo_white: Self = .{ .r = 1, .g = 0.87058824, .b = 0.6784314, .a = 1 };
    pub const navy_blue: Self = .{ .r = 0, .g = 0, .b = 0.5019608, .a = 1 };
    pub const old_lace: Self = .{ .r = 0.99215686, .g = 0.9607843, .b = 0.9019608, .a = 1 };
    pub const olive: Self = .{ .r = 0.5019608, .g = 0.5019608, .b = 0, .a = 1 };
    pub const olive_drab: Self = .{ .r = 0.41960785, .g = 0.5568628, .b = 0.13725491, .a = 1 };
    pub const orange: Self = .{ .r = 1, .g = 0.64705884, .b = 0, .a = 1 };
    pub const orange_red: Self = .{ .r = 1, .g = 0.27058825, .b = 0, .a = 1 };
    pub const orchid: Self = .{ .r = 0.85490197, .g = 0.4392157, .b = 0.8392157, .a = 1 };
    pub const pale_goldenrod: Self = .{ .r = 0.93333334, .g = 0.9098039, .b = 0.6666667, .a = 1 };
    pub const pale_green: Self = .{ .r = 0.59607846, .g = 0.9843137, .b = 0.59607846, .a = 1 };
    pub const pale_turquoise: Self = .{ .r = 0.6862745, .g = 0.93333334, .b = 0.93333334, .a = 1 };
    pub const pale_violet_red: Self = .{ .r = 0.85882354, .g = 0.4392157, .b = 0.5764706, .a = 1 };
    pub const papaya_whip: Self = .{ .r = 1, .g = 0.9372549, .b = 0.8352941, .a = 1 };
    pub const peach_puff: Self = .{ .r = 1, .g = 0.85490197, .b = 0.7254902, .a = 1 };
    pub const peru: Self = .{ .r = 0.8039216, .g = 0.52156866, .b = 0.24705882, .a = 1 };
    pub const pink: Self = .{ .r = 1, .g = 0.7529412, .b = 0.79607844, .a = 1 };
    pub const plum: Self = .{ .r = 0.8666667, .g = 0.627451, .b = 0.8666667, .a = 1 };
    pub const powder_blue: Self = .{ .r = 0.6901961, .g = 0.8784314, .b = 0.9019608, .a = 1 };
    pub const purple: Self = .{ .r = 0.627451, .g = 0.1254902, .b = 0.9411765, .a = 1 };
    pub const rebecca_purple: Self = .{ .r = 0.4, .g = 0.2, .b = 0.6, .a = 1 };
    pub const red: Self = .{ .r = 1, .g = 0, .b = 0, .a = 1 };
    pub const rosy_brown: Self = .{ .r = 0.7372549, .g = 0.56078434, .b = 0.56078434, .a = 1 };
    pub const royal_blue: Self = .{ .r = 0.25490198, .g = 0.4117647, .b = 0.88235295, .a = 1 };
    pub const saddle_brown: Self = .{ .r = 0.54509807, .g = 0.27058825, .b = 0.07450981, .a = 1 };
    pub const salmon: Self = .{ .r = 0.98039216, .g = 0.5019608, .b = 0.44705883, .a = 1 };
    pub const sandy_brown: Self = .{ .r = 0.95686275, .g = 0.6431373, .b = 0.3764706, .a = 1 };
    pub const sea_green: Self = .{ .r = 0.18039216, .g = 0.54509807, .b = 0.34117648, .a = 1 };
    pub const seashell: Self = .{ .r = 1, .g = 0.9607843, .b = 0.93333334, .a = 1 };
    pub const sienna: Self = .{ .r = 0.627451, .g = 0.32156864, .b = 0.1764706, .a = 1 };
    pub const silver: Self = .{ .r = 0.7529412, .g = 0.7529412, .b = 0.7529412, .a = 1 };
    pub const sky_blue: Self = .{ .r = 0.5294118, .g = 0.80784315, .b = 0.92156863, .a = 1 };
    pub const slate_blue: Self = .{ .r = 0.41568628, .g = 0.3529412, .b = 0.8039216, .a = 1 };
    pub const slate_gray: Self = .{ .r = 0.4392157, .g = 0.5019608, .b = 0.5647059, .a = 1 };
    pub const snow: Self = .{ .r = 1, .g = 0.98039216, .b = 0.98039216, .a = 1 };
    pub const spring_green: Self = .{ .r = 0, .g = 1, .b = 0.49803922, .a = 1 };
    pub const steel_blue: Self = .{ .r = 0.27450982, .g = 0.50980395, .b = 0.7058824, .a = 1 };
    pub const tan: Self = .{ .r = 0.8235294, .g = 0.7058824, .b = 0.54901963, .a = 1 };
    pub const teal: Self = .{ .r = 0, .g = 0.5019608, .b = 0.5019608, .a = 1 };
    pub const thistle: Self = .{ .r = 0.84705883, .g = 0.7490196, .b = 0.84705883, .a = 1 };
    pub const tomato: Self = .{ .r = 1, .g = 0.3882353, .b = 0.2784314, .a = 1 };
    pub const transparent: Self = .{ .r = 1, .g = 1, .b = 1, .a = 0 };
    pub const turquoise: Self = .{ .r = 0.2509804, .g = 0.8784314, .b = 0.8156863, .a = 1 };
    pub const violet: Self = .{ .r = 0.93333334, .g = 0.50980395, .b = 0.93333334, .a = 1 };
    pub const web_gray: Self = .{ .r = 0.5019608, .g = 0.5019608, .b = 0.5019608, .a = 1 };
    pub const web_green: Self = .{ .r = 0, .g = 0.5019608, .b = 0, .a = 1 };
    pub const web_maroon: Self = .{ .r = 0.5019608, .g = 0, .b = 0, .a = 1 };
    pub const web_purple: Self = .{ .r = 0.5019608, .g = 0, .b = 0.5019608, .a = 1 };
    pub const wheat: Self = .{ .r = 0.9607843, .g = 0.87058824, .b = 0.7019608, .a = 1 };
    pub const white: Self = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const white_smoke: Self = .{ .r = 0.9607843, .g = 0.9607843, .b = 0.9607843, .a = 1 };
    pub const yellow: Self = .{ .r = 1, .g = 1, .b = 0, .a = 1 };
    pub const yellow_green: Self = .{ .r = 0.6039216, .g = 0.8039216, .b = 0.19607843, .a = 1 };

    pub fn toRgba32(self: Self) u32 {
        var value: u32 = channel8(self.r);
        value = (value << 8) | channel8(self.g);
        value = (value << 8) | channel8(self.b);
        value = (value << 8) | channel8(self.a);
        return value;
    }

    pub fn toArgb32(self: Self) u32 {
        var value: u32 = channel8(self.a);
        value = (value << 8) | channel8(self.r);
        value = (value << 8) | channel8(self.g);
        value = (value << 8) | channel8(self.b);
        return value;
    }

    pub fn toAbgr32(self: Self) u32 {
        var value: u32 = channel8(self.a);
        value = (value << 8) | channel8(self.b);
        value = (value << 8) | channel8(self.g);
        value = (value << 8) | channel8(self.r);
        return value;
    }

    pub fn toRgba64(self: Self) u64 {
        var value: u64 = channel16(self.r);
        value = (value << 16) | channel16(self.g);
        value = (value << 16) | channel16(self.b);
        value = (value << 16) | channel16(self.a);
        return value;
    }

    pub fn toArgb64(self: Self) u64 {
        var value: u64 = channel16(self.a);
        value = (value << 16) | channel16(self.r);
        value = (value << 16) | channel16(self.g);
        value = (value << 16) | channel16(self.b);
        return value;
    }

    pub fn toAbgr64(self: Self) u64 {
        var value: u64 = channel16(self.a);
        value = (value << 16) | channel16(self.b);
        value = (value << 16) | channel16(self.g);
        value = (value << 16) | channel16(self.r);
        return value;
    }

    pub fn getR8(self: Self) i32 {
        return @intFromFloat(std.math.clamp(@round(self.r * C.color_byte_max), 0, C.color_byte_max));
    }

    pub fn setR8(self: *Self, value: i32) void {
        self.r = @as(f32, @floatFromInt(std.math.clamp(value, 0, 255))) / C.color_byte_max;
    }

    pub fn getG8(self: Self) i32 {
        return @intFromFloat(std.math.clamp(@round(self.g * C.color_byte_max), 0, C.color_byte_max));
    }

    pub fn setG8(self: *Self, value: i32) void {
        self.g = @as(f32, @floatFromInt(std.math.clamp(value, 0, 255))) / C.color_byte_max;
    }

    pub fn getB8(self: Self) i32 {
        return @intFromFloat(std.math.clamp(@round(self.b * C.color_byte_max), 0, C.color_byte_max));
    }

    pub fn setB8(self: *Self, value: i32) void {
        self.b = @as(f32, @floatFromInt(std.math.clamp(value, 0, 255))) / C.color_byte_max;
    }

    pub fn getA8(self: Self) i32 {
        return @intFromFloat(std.math.clamp(@round(self.a * C.color_byte_max), 0, C.color_byte_max));
    }

    pub fn setA8(self: *Self, value: i32) void {
        self.a = @as(f32, @floatFromInt(std.math.clamp(value, 0, 255))) / C.color_byte_max;
    }

    pub fn getH(self: Self) f32 {
        const min_rg = @min(self.r, self.g);
        const min = @min(min_rg, self.b);
        const max_rg = @max(self.r, self.g);
        const max = @max(max_rg, self.b);
        const delta = max - min;

        if (delta == 0) return 0;

        var h: f32 = if (self.r == max)
            (self.g - self.b) / delta
        else if (self.g == max)
            2 + (self.b - self.r) / delta
        else
            4 + (self.r - self.g) / delta;

        h /= 6;
        if (h < 0) h += 1;
        return h;
    }

    pub fn getS(self: Self) f32 {
        const min_rg = @min(self.r, self.g);
        const min = @min(min_rg, self.b);
        const max_rg = @max(self.r, self.g);
        const max = @max(max_rg, self.b);
        const delta = max - min;
        return if (max != 0) delta / max else 0;
    }

    pub fn getV(self: Self) f32 {
        const max_rg = @max(self.r, self.g);
        return @max(max_rg, self.b);
    }

    pub fn setH(self: *Self, h: f32) void {
        self.* = fromHsv(h, self.getS(), self.getV(), self.a);
    }

    pub fn setS(self: *Self, s: f32) void {
        self.* = fromHsv(self.getH(), s, self.getV(), self.a);
    }

    pub fn setV(self: *Self, v: f32) void {
        self.* = fromHsv(self.getH(), self.getS(), v, self.a);
    }

    pub fn getOkHslH(self: Self) f32 {
        return clampOkHsl(ok_color.srgbToOkhsl(.{ .r = self.r, .g = self.g, .b = self.b }).h);
    }

    pub fn getOkHslS(self: Self) f32 {
        return clampOkHsl(ok_color.srgbToOkhsl(.{ .r = self.r, .g = self.g, .b = self.b }).s);
    }

    pub fn getOkHslL(self: Self) f32 {
        return clampOkHsl(ok_color.srgbToOkhsl(.{ .r = self.r, .g = self.g, .b = self.b }).l);
    }

    pub fn setOkHslH(self: *Self, h: f32) void {
        self.* = fromOkHsl(h, self.getOkHslS(), self.getOkHslL(), self.a);
    }

    pub fn setOkHslS(self: *Self, s: f32) void {
        self.* = fromOkHsl(self.getOkHslH(), s, self.getOkHslL(), self.a);
    }

    pub fn setOkHslL(self: *Self, l: f32) void {
        self.* = fromOkHsl(self.getOkHslH(), self.getOkHslS(), l, self.a);
    }

    pub fn fromOkHsl(h: f32, s: f32, l: f32, alpha: f32) Self {
        const rgb = ok_color.okhslToSrgb(.{ .h = h, .s = s, .l = l });
        return Self.init(rgb.r, rgb.g, rgb.b, alpha).clamp(Self.black, Self.white);
    }

    pub fn clamp(self: Self, min: Self, max: Self) Self {
        return .{
            .r = std.math.clamp(self.r, min.r, max.r),
            .g = std.math.clamp(self.g, min.g, max.g),
            .b = std.math.clamp(self.b, min.b, max.b),
            .a = std.math.clamp(self.a, min.a, max.a),
        };
    }

    pub fn inverted(self: Self) Self {
        return .{ .r = 1 - self.r, .g = 1 - self.g, .b = 1 - self.b, .a = self.a };
    }

    pub fn lerp(self: Self, to: Self, weight: f32) Self {
        return .{
            .r = self.r + (to.r - self.r) * weight,
            .g = self.g + (to.g - self.g) * weight,
            .b = self.b + (to.b - self.b) * weight,
            .a = self.a + (to.a - self.a) * weight,
        };
    }

    pub fn lightened(self: Self, amount: f32) Self {
        return .{
            .r = self.r + (1 - self.r) * amount,
            .g = self.g + (1 - self.g) * amount,
            .b = self.b + (1 - self.b) * amount,
            .a = self.a,
        };
    }

    pub fn darkened(self: Self, amount: f32) Self {
        return .{
            .r = self.r * (1 - amount),
            .g = self.g * (1 - amount),
            .b = self.b * (1 - amount),
            .a = self.a,
        };
    }

    pub fn blend(self: Self, over: Self) Self {
        const sa = 1 - over.a;
        const alpha = self.a * sa + over.a;
        if (alpha == 0) return .{ .r = 0, .g = 0, .b = 0, .a = 0 };

        return .{
            .r = (self.r * self.a * sa + over.r * over.a) / alpha,
            .g = (self.g * self.a * sa + over.g * over.a) / alpha,
            .b = (self.b * self.a * sa + over.b * over.a) / alpha,
            .a = alpha,
        };
    }

    pub fn getLuminance(self: Self) f32 {
        return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b;
    }

    pub fn srgbToLinear(self: Self) Self {
        return .{
            .r = srgbChannelToLinear(self.r),
            .g = srgbChannelToLinear(self.g),
            .b = srgbChannelToLinear(self.b),
            .a = self.a,
        };
    }

    pub fn linearToSrgb(self: Self) Self {
        return .{
            .r = linearChannelToSrgb(self.r),
            .g = linearChannelToSrgb(self.g),
            .b = linearChannelToSrgb(self.b),
            .a = self.a,
        };
    }

    pub fn isEqualApprox(self: Self, other: Self) bool {
        return isEqualApproxChannel(self.r, other.r) and
            isEqualApproxChannel(self.g, other.g) and
            isEqualApproxChannel(self.b, other.b) and
            isEqualApproxChannel(self.a, other.a);
    }

    pub fn hex(value: u32) Self {
        return .{
            .r = @as(f32, @floatFromInt(value & 0xFF)) / C.color_byte_max,
            .g = @as(f32, @floatFromInt((value >> 8) & 0xFF)) / C.color_byte_max,
            .b = @as(f32, @floatFromInt((value >> 16) & 0xFF)) / C.color_byte_max,
            .a = @as(f32, @floatFromInt((value >> 24) & 0xFF)) / C.color_byte_max,
        };
    }

    pub fn hex64(value: u64) Self {
        return .{
            .r = @as(f32, @floatFromInt(value & 0xFFFF)) / C.color_word_max,
            .g = @as(f32, @floatFromInt((value >> 16) & 0xFFFF)) / C.color_word_max,
            .b = @as(f32, @floatFromInt((value >> 32) & 0xFFFF)) / C.color_word_max,
            .a = @as(f32, @floatFromInt((value >> 48) & 0xFFFF)) / C.color_word_max,
        };
    }

    pub fn fromHsv(h: f32, s: f32, v: f32, alpha: f32) Self {
        if (s == 0) return .{ .r = v, .g = v, .b = v, .a = alpha };

        const hue = @mod(h * 6, 6);
        const index: u32 = @intFromFloat(@floor(hue));
        const f = hue - @floor(hue);
        const p = v * (1 - s);
        const q = v * (1 - s * f);
        const t = v * (1 - s * (1 - f));

        return switch (index) {
            0 => .{ .r = v, .g = t, .b = p, .a = alpha },
            1 => .{ .r = q, .g = v, .b = p, .a = alpha },
            2 => .{ .r = p, .g = v, .b = t, .a = alpha },
            3 => .{ .r = p, .g = q, .b = v, .a = alpha },
            4 => .{ .r = t, .g = p, .b = v, .a = alpha },
            else => .{ .r = v, .g = p, .b = q, .a = alpha },
        };
    }

    pub fn fromRgbe9995(rgbe: u32) Self {
        const r: f32 = @floatFromInt(rgbe & 0x1FF);
        const g: f32 = @floatFromInt((rgbe >> 9) & 0x1FF);
        const b: f32 = @floatFromInt((rgbe >> 18) & 0x1FF);
        const e: f32 = @floatFromInt(rgbe >> 27);
        const multiplier = @exp2(e - 24);
        return .{ .r = r * multiplier, .g = g * multiplier, .b = b * multiplier, .a = 1 };
    }

    pub fn fromRgba8(r8: i32, g8: i32, b8: i32, a8: i32) Self {
        return .{
            .r = @as(f32, @floatFromInt(r8)) / C.color_byte_max,
            .g = @as(f32, @floatFromInt(g8)) / C.color_byte_max,
            .b = @as(f32, @floatFromInt(b8)) / C.color_byte_max,
            .a = @as(f32, @floatFromInt(a8)) / C.color_byte_max,
        };
    }

    fn channel8(value: f32) u32 {
        return @intFromFloat(std.math.clamp(@round(value * C.color_byte_max), 0, 255));
    }

    fn channel16(value: f32) u64 {
        return @intFromFloat(std.math.clamp(@round(value * C.color_word_max), 0, C.color_word_max));
    }

    fn isEqualApproxChannel(a: f32, b: f32) bool {
        if (a == b) return true;
        var tolerance = C.cmp_epsilon * @abs(a);
        if (tolerance < C.cmp_epsilon) tolerance = C.cmp_epsilon;
        return @abs(a - b) < tolerance;
    }

    fn clampOkHsl(value: f32) f32 {
        if (std.math.isNan(value)) return 0;
        return std.math.clamp(value, 0, 1);
    }

    fn srgbChannelToLinear(value: f32) f32 {
        return if (value < 0.04045)
            value * (1.0 / 12.92)
        else
            std.math.pow(f32, (value + 0.055) * (1.0 / (1.0 + 0.055)), 2.4);
    }

    fn linearChannelToSrgb(value: f32) f32 {
        return if (value < 0.0031308)
            12.92 * value
        else
            (1.0 + 0.055) * std.math.pow(f32, value, 1.0 / 2.4) - 0.055;
    }
};

test "Color layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Color));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(Color));
}

test "Color encoding" {
    const red = Color.init(1, 0, 0, 1);
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), red.toRgba32());
    try std.testing.expectEqual(@as(u32, 0xFFFF0000), red.toArgb32());
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), red.toAbgr32());
    try std.testing.expectEqual(@as(u64, 0xFFFF00000000FFFF), red.toRgba64());

    try std.testing.expectEqual(red, Color.hex(0xFF0000FF));
    try std.testing.expectEqual(red, Color.hex64(0xFFFF00000000FFFF));
}

test "Color HSV and conversions" {
    const cyan = Color.fromHsv(0.5, 1, 1, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), cyan.r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), cyan.g, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), cyan.b, 0.00001);

    const linear = Color.init(0.5, 0.5, 0.5, 1).srgbToLinear();
    const round_trip = linear.linearToSrgb();
    try std.testing.expect(round_trip.isEqualApprox(Color.init(0.5, 0.5, 0.5, 1)));

    try std.testing.expect(redEqualsColor());
}

fn redEqualsColor() bool {
    return Color.red.isEqualApprox(Color.init(1, 0, 0, 1));
}

test "Color operations" {
    const base = Color.init(0.25, 0.5, 0.75, 1);

    try std.testing.expectApproxEqAbs(@as(f32, 0.625), base.lerp(Color.white, 0.5).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), base.lightened(1).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), base.darkened(1).r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), base.inverted().r, 0.00001);
    try std.testing.expect(base.getLuminance() > 0);

    const clamped = Color.init(-1, 2, 0.5, 1).clamp(Color.black, Color.white);
    try std.testing.expectEqual(Color.init(0, 1, 0.5, 1), clamped);

    const blended = Color.init(1, 0, 0, 0.5).blend(Color.init(0, 0, 1, 0.5));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), blended.r, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0 / 3.0), blended.b, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), blended.a, 0.00001);
}

test "Color computed members" {
    var value = Color.init(0.2, 0.4, 0.8, 1);

    value.setR8(128);
    value.setG8(64);
    value.setB8(32);
    value.setA8(255);
    try std.testing.expectEqual(@as(i32, 128), value.getR8());
    try std.testing.expectEqual(@as(i32, 64), value.getG8());
    try std.testing.expectEqual(@as(i32, 32), value.getB8());
    try std.testing.expectEqual(@as(i32, 255), value.getA8());

    const hsv = Color.init(0.2, 0.4, 0.8, 1);
    const hue = hsv.getH();
    const saturation = hsv.getS();
    const brightness = hsv.getV();
    value.setH(hue);
    value.setS(saturation);
    value.setV(brightness);
    try std.testing.expect(value.getH() >= 0 and value.getH() <= 1);

    const okhsl = Color.fromOkHsl(0.5, 0.5, 0.5, 1);
    try std.testing.expect(okhsl.getOkHslH() >= 0);
    value.setOkHslH(0.25);
    value.setOkHslS(0.5);
    value.setOkHslL(0.5);
    try std.testing.expect(value.getOkHslH() >= 0);
}

test "all Color methods compile" {
    const value = Color.init(0.25, 0.5, 0.75, 1);
    const other = Color.init(0.1, 0.2, 0.3, 0.4);

    std.mem.doNotOptimizeAway(value.toRgba32());
    std.mem.doNotOptimizeAway(value.toArgb32());
    std.mem.doNotOptimizeAway(value.toAbgr32());
    std.mem.doNotOptimizeAway(value.toRgba64());
    std.mem.doNotOptimizeAway(value.toArgb64());
    std.mem.doNotOptimizeAway(value.toAbgr64());
    std.mem.doNotOptimizeAway(value.clamp(Color.black, Color.white));
    std.mem.doNotOptimizeAway(value.inverted());
    std.mem.doNotOptimizeAway(value.lerp(other, 0.5));
    std.mem.doNotOptimizeAway(value.lightened(0.5));
    std.mem.doNotOptimizeAway(value.darkened(0.5));
    std.mem.doNotOptimizeAway(value.blend(other));
    std.mem.doNotOptimizeAway(value.getLuminance());
    std.mem.doNotOptimizeAway(value.srgbToLinear());
    std.mem.doNotOptimizeAway(value.linearToSrgb());
    std.mem.doNotOptimizeAway(value.isEqualApprox(other));
    std.mem.doNotOptimizeAway(Color.hex(0x11223344));
    std.mem.doNotOptimizeAway(Color.hex64(0x1122334455667788));
    std.mem.doNotOptimizeAway(Color.fromHsv(0.5, 0.5, 0.5, 1));
    std.mem.doNotOptimizeAway(Color.fromOkHsl(0.5, 0.5, 0.5, 1));
    std.mem.doNotOptimizeAway(value.getOkHslH());
    std.mem.doNotOptimizeAway(value.getOkHslS());
    std.mem.doNotOptimizeAway(value.getOkHslL());
    std.mem.doNotOptimizeAway(Color.fromRgbe9995(0x12345678));
    std.mem.doNotOptimizeAway(Color.fromRgba8(1, 2, 3, 4));
}

test "Color constants" {
    try std.testing.expect(Color.alice_blue.isEqualApprox(Color.init(0.9411765, 0.972549, 1, 1)));
    try std.testing.expect(Color.transparent.isEqualApprox(Color.init(1, 1, 1, 0)));
    try std.testing.expect(Color.web_gray.isEqualApprox(Color.init(0.5019608, 0.5019608, 0.5019608, 1)));
}

const std = @import("std");
const bindings = @import("bindings");
const auto = @import("../auto/auto.zig");
const generated_namespace = @import("generated/color.zig");
const constants = @import("constants.zig");
const ok_color = @import("ok_color.zig");
