//! `Conversion` type-attached marker identity and discovery.
//!
//! Discovery scans a type's declarations for a `Conversion` marker, so the
//! declaration name is free. `annotations/conversion.zig`'s `find`/
//! `MarkerEngine` are internal to the annotation module; the test-only
//! `godot.internal.conversion.engineType`/`variantType` exercise both, so
//! identity is pinned here.

const Duration = struct {
    millis: i32,

    /// Any declaration name is a valid marker attachment.
    pub const Wire = godot.annotations.Conversion(.{
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

/// Same payload declarations as a Conversion marker, but no marker kind.
const FakeMarker = struct {
    pub const Engine = i32;

    fn toEngine(value: i32) i32 {
        return value;
    }

    fn fromEngine(value: i32) i32 {
        return value;
    }
};

/// A lookalike declaration is ignored; the real marker with another name wins.
const Mixed = struct {
    millis: i32,

    pub const Decoy = FakeMarker;
    pub const MapToInt = godot.annotations.Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Mixed) i32 {
        return self.millis;
    }

    fn fromEngine(millis: i32) Mixed {
        return .{ .millis = millis };
    }
};

/// Only a lookalike: not a conversion type.
const LookalikeOnly = struct {
    pub const Decoy = FakeMarker;
};

fn checkConversionMarker() void {
    const Marker = Duration.Wire;
    if (comptime godot.annotations.marker.kindOf(Marker) != .conversion)
        @compileError("Conversion markers must declare marker.Kind.conversion");
    if (comptime !godot.annotations.marker.is(Marker, .conversion))
        @compileError("Conversion markers must identify as the conversion family");
    if (comptime godot.annotations.marker.is(Marker, .override))
        @compileError("Conversion markers must not identify as another family");
    if (@TypeOf(Marker.marker) != godot.annotations.marker.Kind)
        @compileError("Conversion markers must expose marker.Kind");

    // Discovery: engineType goes through annotations.conversion.find and
    // MarkerEngine for the attached marker, whatever it is named.
    if (comptime godot.internal.conversion.engineType(Duration) != i32)
        @compileError("conversion discovery must find the Conversion marker");
    if (comptime godot.internal.conversion.variantType(Duration) != .int)
        @compileError("conversion discovery must use the marker's engine type");
    if (comptime godot.internal.conversion.engineType(Mixed) != i32)
        @compileError("a lookalike declaration must not hide the real marker");
    if (comptime godot.internal.conversion.support(LookalikeOnly).variant)
        @compileError("a markerless lookalike must not be treated as a conversion");
    if (godot.annotations.marker.kindOf(FakeMarker) != null)
        @compileError("a Conversion lookalike must not declare an annotation marker");
}

comptime {
    checkConversionMarker();
}

test "Conversion marker identity survives discovery" {
    comptime checkConversionMarker();
    var variant: godot.builtins.Variant = undefined;
    godot.internal.conversion.encodeVariant(Duration, Duration{ .millis = 13 }, &variant);
    const decoded = godot.internal.conversion.decodeVariant(Duration, &variant) orelse
        @panic("conversion test: decoded Duration is null");
    try std.testing.expectEqual(@as(i32, 13), decoded.millis);
}

const std = @import("std");

const godot = @import("godot");
