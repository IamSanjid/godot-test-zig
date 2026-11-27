//! Method registration coverage: metadata and adapter analysis for every
//! supported signature shape, plus engine-free direct invocation of both
//! adapters for scalar and scalar-converter signatures.
//!
//! `StringName` construction and dispatch need an initialized engine, so the
//! registration path is analyzed, never executed. Canonical scalar conversion
//! does not touch the engine, which is what the direct invocation tests use.

/// Converts to and from an engine scalar, so both adapters stay engine-free.
const Duration = struct {
    millis: i32,

    pub const GodotConversion = godot.annotations.Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Duration) i32 {
        return self.millis;
    }

    fn fromEngine(millis: i32) Duration {
        return .{ .millis = millis };
    }
};

/// Counts `deinit` calls so the adapter release policy is observable without an
/// engine: an encoded converter result owns its decode.
var deinit_count: usize = 0;

const Counted = struct {
    value: i32,

    pub const GodotConversion = godot.annotations.Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Counted) i32 {
        return self.value;
    }

    fn fromEngine(value: i32) Counted {
        return .{ .value = value };
    }

    pub fn deinit(self: *Counted) void {
        _ = self;
        deinit_count += 1;
    }
};

const Fixture = struct {
    health: i32 = 0,

    pub const RegMethods = godot.annotations.Methods(.{
        godot.annotations.Method(.add, .{ .arg_names = .{ "left", "right" } }),
        godot.annotations.Method(.currentHealth, .{}),
        godot.annotations.Method(.ping, .{ .arg_names = .{"target"} }),
        godot.annotations.Method(.wait, .{ .arg_names = .{"duration"} }),
        godot.annotations.Method(.version, .{ .is_static = true }),
        godot.annotations.Method(.reset, .{ .is_static = true }),
        godot.annotations.Method(.echo, .{ .arg_names = .{"value"} }),
        godot.annotations.Method(.nodeOrDefault, .{ .arg_names = .{"node"} }),
        godot.annotations.Method(.combine, .{
            .is_static = true,
            .arg_names = .{ "left", "right" },
        }),
        godot.annotations.Method(.setHealth, .{ .arg_names = .{"value"} }),
        godot.annotations.Method(.label, .{ .arg_names = .{"text"} }),
        godot.annotations.Method(.consume, .{ .arg_names = .{"count"} }),
        godot.annotations.Method(.accumulate, .{ .arg_names = .{ "first", "second" } }),
    });

    pub fn add(self: *@This(), left: i32, right: i32) i32 {
        _ = self;
        return left + right;
    }

    /// A `*const` self parameter sets the const method flag.
    pub fn currentHealth(self: *const @This()) i32 {
        return self.health;
    }

    pub fn ping(self: *@This(), target: ?*classes.core.Node) i32 {
        _ = self;
        return if (target == null) 0 else 1;
    }

    pub fn wait(self: *@This(), duration: Duration) Duration {
        _ = self;
        return duration;
    }

    pub fn version() i32 {
        return 1;
    }

    pub fn reset() void {}

    /// `Variant` registers untyped (`.nil`); the adapters are engine-facing.
    pub fn echo(self: *@This(), value: builtins.Variant) builtins.Variant {
        _ = self;
        _ = value;
        return builtins.Variant.nil;
    }

    pub fn nodeOrDefault(self: *@This(), node: ?*classes.core.Node) ?*classes.core.Node {
        _ = self;
        return node;
    }

    pub fn combine(left: i32, right: i32) i32 {
        return left + right;
    }

    pub fn setHealth(self: *@This(), value: i32) void {
        self.health = value;
    }

    /// An owned builtin arg is borrow-like (the adapter copies it); an owned
    /// builtin result covers the metadata and release paths in analysis.
    pub fn label(self: *@This(), text: builtins.String) builtins.String {
        _ = self;
        _ = text;
        return builtins.String.fromLatin1("label");
    }

    /// A converter result with `deinit` proves each encoded result is released
    /// once. Owning converters cannot be arguments, so it takes a scalar.
    pub fn consume(self: *@This(), count: i32) Counted {
        _ = self;
        return .{ .value = count * 2 };
    }

    /// A direct argument and a converter argument: the second one can fail after
    /// the first decode.
    pub fn accumulate(self: *@This(), first: i32, second: Duration) i32 {
        _ = self;
        return first + second.millis;
    }
};

const NoMethods = struct {};

const FixtureEntries = godot.annotations.findMethods(Fixture);

fn FixtureEntry(comptime name: []const u8) type {
    inline for (FixtureEntries) |Entry| {
        if (std.mem.eql(u8, Entry.name, name)) return Entry;
    }
    @compileError("method registration tests: no method named '" ++ name ++ "'");
}

/// Neither registration path may run here: both construct engine `StringName`s.
fn checkRegistrationAnalysis() void {
    var class_name: builtins.StringName = undefined;
    methods.registerMethods(Fixture, null, &class_name);
    methods.registerMethods(NoMethods, null, &class_name);
    _ = classdb.postRegistrationCallback(Fixture);
    _ = classdb.postRegistrationCallback(NoMethods);
}

fn intVariant(value: i32) builtins.Variant {
    return builtins.Variant.borrow(i32, value).get();
}

test "method metadata and adapters analyze without engine calls" {
    _ = &checkRegistrationAnalysis;
}

test "class-level methods produce a post-registration callback" {
    comptime {
        if (classdb.postRegistrationCallback(Fixture) == null) @compileError(
            "a class with methods must get a post-registration callback",
        );
        if (classdb.postRegistrationCallback(NoMethods) != null) @compileError(
            "a class without class-level metadata must get no post-registration callback",
        );
    }
}

test "method flags derive from the resolved entry" {
    const instance_flags: interface.ClassMethodFlags =
        @bitCast(methods.methodFlags(FixtureEntry("add")));
    try std.testing.expect(instance_flags.normal);
    try std.testing.expect(!instance_flags.@"const");
    try std.testing.expect(!instance_flags.static);

    const const_flags: interface.ClassMethodFlags =
        @bitCast(methods.methodFlags(FixtureEntry("current_health")));
    try std.testing.expect(const_flags.@"const");
    try std.testing.expect(!const_flags.static);

    const static_flags: interface.ClassMethodFlags =
        @bitCast(methods.methodFlags(FixtureEntry("version")));
    try std.testing.expect(static_flags.static);
    try std.testing.expect(!static_flags.@"const");
}

test "call_func decodes scalar arguments and encodes the return" {
    var instance: Fixture = .{};
    const cb = methods.callbacks(FixtureEntry("add"));
    var left = intVariant(2);
    var right = intVariant(40);
    const args = [_]interface.ConstVariantPtr{ &left, &right };
    var ret = builtins.Variant.nil;
    var error_info: interface.CallError = .{};

    cb.call_func.?(null, &instance, @ptrCast(&args), 2, &ret, &error_info);

    try std.testing.expectEqual(interface.CallErrorType.ok, error_info.@"error");
    try std.testing.expectEqual(@as(i32, 42), ret.as(i32).?);
}

test "call_func reports argument count and type errors" {
    var instance: Fixture = .{};
    const cb = methods.callbacks(FixtureEntry("add"));
    var left = intVariant(2);
    var right = intVariant(40);
    const args = [_]interface.ConstVariantPtr{ &left, &right };
    var ret = intVariant(7);
    var error_info: interface.CallError = .{};

    cb.call_func.?(null, &instance, @ptrCast(&args), 1, &ret, &error_info);
    try std.testing.expectEqual(interface.CallErrorType.too_few_arguments, error_info.@"error");
    try std.testing.expectEqual(interface.VariantType.nil, ret.tag);

    error_info = .{};
    cb.call_func.?(null, &instance, null, 3, &ret, &error_info);
    try std.testing.expectEqual(interface.CallErrorType.too_many_arguments, error_info.@"error");
    try std.testing.expectEqual(interface.VariantType.nil, ret.tag);

    var float_argument = builtins.Variant.borrow(f32, 1.5).get();
    const wrong_args = [_]interface.ConstVariantPtr{ &float_argument, &right };
    error_info = .{};
    cb.call_func.?(null, &instance, @ptrCast(&wrong_args), 2, &ret, &error_info);
    try std.testing.expectEqual(interface.CallErrorType.invalid_argument, error_info.@"error");
    try std.testing.expectEqual(@as(i32, 0), error_info.argument);
    try std.testing.expectEqual(
        @as(i32, @intCast(@backingInt(interface.VariantType.int))),
        error_info.expected,
    );
}

test "call_func reports a null instance for instance methods" {
    const cb = methods.callbacks(FixtureEntry("current_health"));
    var ret = builtins.Variant.nil;
    var error_info: interface.CallError = .{};

    cb.call_func.?(null, null, null, 0, &ret, &error_info);

    try std.testing.expectEqual(interface.CallErrorType.instance_is_null, error_info.@"error");
    try std.testing.expectEqual(interface.VariantType.nil, ret.tag);
}

test "static and void call_func adapters" {
    var ret = builtins.Variant.nil;
    var error_info: interface.CallError = .{};
    const version_cb = methods.callbacks(FixtureEntry("version"));
    version_cb.call_func.?(null, null, null, 0, &ret, &error_info);
    try std.testing.expectEqual(interface.CallErrorType.ok, error_info.@"error");
    try std.testing.expectEqual(@as(i32, 1), ret.as(i32).?);

    var instance: Fixture = .{};
    const set_cb = methods.callbacks(FixtureEntry("set_health"));
    var value = intVariant(55);
    const args = [_]interface.ConstVariantPtr{&value};
    error_info = .{};
    // A return-less method may receive a null return slot.
    set_cb.call_func.?(null, &instance, @ptrCast(&args), 1, null, &error_info);
    try std.testing.expectEqual(interface.CallErrorType.ok, error_info.@"error");
    try std.testing.expectEqual(@as(i32, 55), instance.health);
}

test "ptrcall decodes scalar slots and writes the return" {
    var instance: Fixture = .{ .health = 5 };
    const add_cb = methods.callbacks(FixtureEntry("add"));
    var left: i64 = 2;
    var right: i64 = 40;
    const add_args = [_]interface.ConstTypePtr{ &left, &right };
    var add_return: i64 = 0;
    add_cb.ptrcall_func.?(null, &instance, @ptrCast(&add_args), &add_return);
    try std.testing.expectEqual(@as(i64, 42), add_return);

    const health_cb = methods.callbacks(FixtureEntry("current_health"));
    var health_return: i64 = 0;
    health_cb.ptrcall_func.?(null, &instance, null, &health_return);
    try std.testing.expectEqual(@as(i64, 5), health_return);

    const version_cb = methods.callbacks(FixtureEntry("version"));
    var version_return: i64 = 0;
    version_cb.ptrcall_func.?(null, null, null, &version_return);
    try std.testing.expectEqual(@as(i64, 1), version_return);
}

test "ptrcall void and converter adapters" {
    var instance: Fixture = .{};
    const set_cb = methods.callbacks(FixtureEntry("set_health"));
    var health_slot: i64 = 55;
    const set_args = [_]interface.ConstTypePtr{&health_slot};
    set_cb.ptrcall_func.?(null, &instance, @ptrCast(&set_args), null);
    try std.testing.expectEqual(@as(i32, 55), instance.health);

    const reset_cb = methods.callbacks(FixtureEntry("reset"));
    reset_cb.ptrcall_func.?(null, null, null, null);

    const wait_cb = methods.callbacks(FixtureEntry("wait"));
    var duration_slot: i64 = 12;
    const wait_args = [_]interface.ConstTypePtr{&duration_slot};
    var wait_return: i64 = 0;
    wait_cb.ptrcall_func.?(null, &instance, @ptrCast(&wait_args), &wait_return);
    try std.testing.expectEqual(@as(i64, 12), wait_return);
}

test "call_func reports a later argument mismatch after earlier decodes" {
    var instance: Fixture = .{};
    const cb = methods.callbacks(FixtureEntry("accumulate"));
    var first = intVariant(3);
    var second = builtins.Variant.borrow(f32, 1.5).get();
    const args = [_]interface.ConstVariantPtr{ &first, &second };
    var ret = intVariant(9);
    var error_info: interface.CallError = .{};

    cb.call_func.?(null, &instance, @ptrCast(&args), 2, &ret, &error_info);

    try std.testing.expectEqual(interface.CallErrorType.invalid_argument, error_info.@"error");
    try std.testing.expectEqual(@as(i32, 1), error_info.argument);
    try std.testing.expectEqual(interface.VariantType.nil, ret.tag);
}

test "converter results are released once per call" {
    var instance: Fixture = .{};

    deinit_count = 0;
    {
        const cb = methods.callbacks(FixtureEntry("consume"));
        var count = intVariant(21);
        const args = [_]interface.ConstVariantPtr{&count};
        var ret = builtins.Variant.nil;
        var error_info: interface.CallError = .{};
        cb.call_func.?(null, &instance, @ptrCast(&args), 1, &ret, &error_info);
        try std.testing.expectEqual(interface.CallErrorType.ok, error_info.@"error");
        try std.testing.expectEqual(@as(i32, 42), ret.as(i32).?);
    }
    // One encoded converter result, released once.
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    deinit_count = 0;
    {
        const cb = methods.callbacks(FixtureEntry("consume"));
        var count: i64 = 21;
        const args = [_]interface.ConstTypePtr{&count};
        var out: i64 = 0;
        cb.ptrcall_func.?(null, &instance, @ptrCast(&args), &out);
        try std.testing.expectEqual(@as(i64, 42), out);
    }
    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

const std = @import("std");

const godot = @import("godot");
const annotations = godot.annotations;
const builtins = godot.builtins;
const classes = godot.classes;
const interface = godot.bindings.interface;
const classdb = godot.registration.classdb;
const methods = godot.registration.methods;
