//! `Method`/`Methods` declaration discovery and signature shape coverage.
//!
//! Duplicate engine names and signature mismatches are compile errors and
//! therefore cannot be exercised here; `resolveMethod` and `validateSignature`
//! report them. Discovery itself is analyzed on every build because the entry
//! types are built at comptime.

const Fixture = struct {
    pub const RegMethods = godot.annotations.Methods(.{
        godot.annotations.Method(.ping, .{ .arg_names = .{"target"} }),
        godot.annotations.Method(.currentHealth, .{}),
        godot.annotations.Method(.version, .{ .name = "engine_version", .is_static = true }),
        godot.annotations.Method(helper, .{ .name = "helper", .arg_names = .{"value"} }),
        godot.annotations.Method(.scale, .{}),
        godot.annotations.Method(staticHelper, .{
            .name = "static_helper",
            .arg_names = .{ "first", "second" },
            .is_static = true,
        }),
    });

    /// A second container proves flattening and that the declaration name is free.
    pub const More = godot.annotations.Methods(.{
        godot.annotations.Method(.reset, .{ .is_static = true }),
        godot.annotations.Method(.combine, .{
            .is_static = true,
            .arg_names = .{ "left", "right" },
        }),
    });

    pub fn ping(self: *@This(), target: ?*godot.classes.core.Node) i32 {
        _ = self;
        _ = target;
        return 0;
    }

    /// `*const` self derives the const flag and the tag converts to an engine name.
    pub fn currentHealth(self: *const @This()) i32 {
        _ = self;
        return 100;
    }

    pub fn version() i32 {
        return 1;
    }

    fn helper(self: *@This(), value: i32) void {
        _ = self;
        _ = value;
    }

    /// No `.arg_names`: registration falls back to `arg0`, `arg1`, ...
    pub fn scale(self: *@This(), factor: f32) void {
        _ = self;
        _ = factor;
    }

    /// Direct references do not need a public declaration.
    fn staticHelper(first: f32, second: ?*godot.classes.core.Node) f64 {
        _ = first;
        _ = second;
        return 0;
    }

    pub fn reset() void {}

    /// A static method's parameters are all engine arguments.
    pub fn combine(left: i32, right: i32) i32 {
        return left + right;
    }
};

const NoMethods = struct {};

/// A nested namespace is not a `Methods` container.
const NamespaceOwner = struct {
    pub const Nested = struct {
        pub const ping = godot.annotations.Method(.ping, .{});
    };
};

/// Payload shape without the marker kind: the kind fast-path must skip it.
const PayloadLookalikeOwner = struct {
    pub const Lookalike = struct {
        pub const methods = .{};
    };
};

/// Marker kind and payload shape, but not produced by `Methods`: discovery's
/// identity re-derivation must reject it.
const KindLookalikeOwner = struct {
    pub const Lookalike = struct {
        pub const marker = godot.annotations.marker.Kind.methods;
        pub const methods = .{};
    };
};

/// A `Method` marker placed directly on the class is not a container.
const LooseMethodOwner = struct {
    pub const Loose = godot.annotations.Method(loose, .{ .name = "loose" });

    fn loose(self: *@This()) void {
        _ = self;
    }
};

/// A custom converter argument is validated through the conversion layer like
/// every other engine-facing surface.
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

/// Method arguments are borrow-like: a direct managed builtin and a scalar-engine
/// converter argument both validate, and a converter return stays valid.
const ConverterFixture = struct {
    pub const RegMethods = godot.annotations.Methods(.{
        godot.annotations.Method(.wait, .{ .arg_names = .{"duration"} }),
        godot.annotations.Method(.label, .{ .arg_names = .{"text"} }),
    });

    pub fn wait(self: *@This(), duration: Duration) Duration {
        _ = self;
        return duration;
    }

    pub fn label(self: *@This(), text: godot.builtins.String) godot.builtins.String {
        _ = self;
        _ = text;
        return godot.builtins.String.fromLatin1("label");
    }
};

fn checkMethodDiscovery() void {
    const entries = godot.annotations.findMethods(Fixture);
    if (entries.len != 8) @compileError("findMethods must flatten every Methods container in declaration order");

    const expected_names = [_][]const u8{
        "ping",
        "current_health",
        "engine_version",
        "helper",
        "scale",
        "static_helper",
        "reset",
        "combine",
    };
    inline for (expected_names, 0..) |expected, index| {
        if (!std.mem.eql(u8, entries[index].name, expected))
            @compileError("method " ++ expected ++ " must be discovered in declaration order");
    }

    if (entries[0].is_static) @compileError("a self-taking method is an instance method");
    if (!entries[1].is_const) @compileError("a `*const T` self parameter derives the const flag");
    if (entries[1].is_static) @compileError("a `*const T` self parameter is still an instance method");
    if (!entries[2].is_static) @compileError(".is_static must be preserved");
    if (!entries[6].is_static) @compileError("a second container's static method must be discovered");
    if (!entries[7].is_static) @compileError("a static method's parameters are all engine arguments");

    const expected_arg_counts = [_]usize{ 1, 0, 0, 1, 1, 2, 0, 2 };
    inline for (expected_arg_counts, 0..) |expected, index| {
        if (entries[index].arg_count != expected) @compileError("engine arg counts must exclude self");
    }

    if (entries[0].arg_names.len != 1 or !std.mem.eql(u8, entries[0].arg_names[0], "target"))
        @compileError("explicit .arg_names must be preserved");
    if (entries[1].arg_names.len != 0) @compileError("a method without .arg_names reports none");
    if (entries[3].arg_names.len != 1 or !std.mem.eql(u8, entries[3].arg_names[0], "value"))
        @compileError("a direct reference's .arg_names must be preserved");
    if (entries[5].arg_names.len != 2 or !std.mem.eql(u8, entries[5].arg_names[0], "first"))
        @compileError("static method argument names must be preserved");
    if (entries[7].arg_names.len != 2 or !std.mem.eql(u8, entries[7].arg_names[0], "left"))
        @compileError("a static method's argument names must be preserved");

    if (!std.mem.eql(u8, entries[0].argName(0), "target")) @compileError("argName reports the explicit name");
    if (!std.mem.eql(u8, entries[4].argName(0), "arg0")) @compileError("argName falls back to arg<index>");
    if (!std.mem.eql(u8, entries[5].argName(1), "second")) @compileError("argName covers trailing arguments");
    if (!std.mem.eql(u8, entries[7].argName(1), "right")) @compileError("argName covers static arguments");

    if (entries[0].Fn != @TypeOf(Fixture.ping)) @compileError("the entry Fn type must be the implementation type");
    if (entries[0].implementation != Fixture.ping) @compileError("an enum literal resolves to the class function");
    if (entries[3].implementation != Fixture.helper) @compileError("a direct reference keeps the function value");

    if (godot.annotations.findMethods(NoMethods).len != 0)
        @compileError("classes without a Methods container must report none");
    if (godot.annotations.findMethods(NamespaceOwner).len != 0)
        @compileError("a nested namespace is not a Methods container");
    if (godot.annotations.findMethods(PayloadLookalikeOwner).len != 0)
        @compileError("a payload-only lookalike must not be discovered without the marker kind");
    if (godot.annotations.findMethods(KindLookalikeOwner).len != 0)
        @compileError("a Methods lookalike must not be discovered by declaring the kind");
    if (godot.annotations.findMethods(LooseMethodOwner).len != 0)
        @compileError("a loose Method marker is not a Methods container");

    if (Fixture.RegMethods.marker != godot.annotations.marker.Kind.methods)
        @compileError("Methods containers must declare marker.Kind.methods");
    if (Fixture.RegMethods.methods[0].marker != godot.annotations.marker.Kind.method)
        @compileError("Method markers must declare marker.Kind.method");
    if (godot.annotations.marker.is(Fixture.RegMethods, .method))
        @compileError("a Methods container must not identify as one Method marker");
    if (godot.annotations.marker.is(Fixture.RegMethods.methods[0], .methods))
        @compileError("a Method marker must not identify as the Methods family");
    if (godot.annotations.marker.kindOf(PayloadLookalikeOwner.Lookalike) != null)
        @compileError("a payload-only lookalike must not declare an annotation marker");
    if (godot.annotations.marker.kindOf(KindLookalikeOwner.Lookalike) !=
        godot.annotations.marker.Kind.methods)
        @compileError("a kind lookalike declares the kind; identity still gates discovery");
    if (KindLookalikeOwner.Lookalike == godot.annotations.Methods(.{}))
        @compileError("a hand-written container is not the canonical Methods type");
}

fn checkBorrowLikeArguments() void {
    const entries = godot.annotations.findMethods(ConverterFixture);
    if (entries.len != 2) @compileError("borrow-like arguments must not hide the methods");
    if (entries[0].arg_count != 1) @compileError("the converter argument is one engine argument");
    if (entries[0].Fn != @TypeOf(ConverterFixture.wait)) @compileError("converter methods keep their signature");
    if (entries[1].arg_count != 1) @compileError("the managed builtin argument is one engine argument");
    if (comptime godot.internal.conversion.engineType(Duration) != i32)
        @compileError("converter arguments must resolve through the conversion layer");
    if (comptime !godot.internal.conversion.methodArgumentIsBorrowed(Duration))
        @compileError("scalar-engine converter arguments are call-scoped borrowed");
    if (comptime !godot.internal.conversion.methodArgumentIsBorrowed(godot.builtins.String))
        @compileError("direct managed builtin arguments are call-scoped borrowed");
}

comptime {
    checkMethodDiscovery();
    checkBorrowLikeArguments();
}

test "methods are flattened across containers in declaration order" {
    const entries = comptime godot.annotations.findMethods(Fixture);
    try std.testing.expectEqual(@as(usize, 8), entries.len);
    try std.testing.expectEqualStrings("ping", entries[0].name);
    try std.testing.expectEqualStrings("current_health", entries[1].name);
    try std.testing.expectEqualStrings("engine_version", entries[2].name);
    try std.testing.expectEqualStrings("helper", entries[3].name);
    try std.testing.expectEqualStrings("static_helper", entries[5].name);
    try std.testing.expectEqualStrings("reset", entries[6].name);
    try std.testing.expectEqualStrings("combine", entries[7].name);
}

test "method signature shape derives the engine flags" {
    const entries = comptime godot.annotations.findMethods(Fixture);
    try std.testing.expect(!entries[0].is_static);
    try std.testing.expect(entries[1].is_const);
    try std.testing.expect(!entries[1].is_static);
    try std.testing.expect(entries[2].is_static);
    try std.testing.expect(!entries[6].is_const);
    try std.testing.expectEqual(@as(usize, 2), entries[5].arg_count);
    try std.testing.expectEqual(@as(usize, 2), entries[7].arg_count);
}

test "explicit and fallback argument names" {
    const entries = comptime godot.annotations.findMethods(Fixture);
    try std.testing.expectEqual(@as(usize, 1), entries[0].arg_names.len);
    try std.testing.expectEqualStrings("target", entries[0].arg_names[0]);
    try std.testing.expectEqualStrings("arg0", entries[4].argName(0));
    try std.testing.expectEqualStrings("second", entries[5].argName(1));
    try std.testing.expectEqualStrings("right", entries[7].argName(1));
}

const std = @import("std");

const godot = @import("godot");
