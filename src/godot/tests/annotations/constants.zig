//! `Constants` declaration discovery and type-derived property hints.
//!
//! `typeHint`/`findEnumName` are internal; the same behavior is exercised through
//! `godot.annotations.property.descriptors`, which applies both to visible `Property`
//! fields and enriches them with same-class registered metadata.

const ConstantsFixture = struct {
    pub const ClassConstants = godot.annotations.Constants(struct {
        pub const MAX_HEALTH = 100;
        pub const maxSpeed: u32 = 42;
        pub const State = enum(i32) { idle, running = 3 };
        pub const Flags = bitpack struct(u32) {
            first: bool = false,
            second: bool = false,
            _pad0: u30 = 0,
        };
    });

    /// A second marker proves the declaration name is free and entries append.
    pub const More = godot.annotations.Constants(struct {
        pub const EXTRA = 5;
    });
};

fn checkConstantDiscovery() void {
    const entries = godot.annotations.findConstants(ConstantsFixture);
    if (entries.len != 7) @compileError("findConstants must expand enum and bitfield declarations across markers");

    if (!std.mem.eql(u8, entries[0].name, "MAX_HEALTH")) @compileError("constant names are converted to engine constants");
    if (entries[0].enum_name.len != 0) @compileError("loose constants have no enum name");
    if (entries[0].value != 100) @compileError("loose constants keep their value");
    if (!std.mem.eql(u8, entries[1].name, "MAX_SPEED")) @compileError("camelCase constant names are converted");
    if (entries[1].enum_name.len != 0) @compileError("loose constants have no enum name");

    if (!std.mem.eql(u8, entries[2].enum_name, "State")) @compileError("enum variants carry their enum name");
    if (!std.mem.eql(u8, entries[2].name, "IDLE")) @compileError("enum variants are converted to engine constants");
    if (entries[2].value != 0) @compileError("enum variants keep their value");
    if (!std.mem.eql(u8, entries[3].name, "RUNNING")) @compileError("enum variants are converted to engine constants");
    if (entries[3].value != 3) @compileError("explicit enum values are preserved");

    if (!std.mem.eql(u8, entries[4].enum_name, "Flags")) @compileError("bitfield flags carry their enum name");
    if (!std.mem.eql(u8, entries[4].name, "FIRST")) @compileError("bitfield flags are converted to engine constants");
    if (entries[4].value != 1 or !entries[4].is_bitfield) @compileError("the first bitfield flag is bit 0");
    if (entries[5].value != 2) @compileError("the second bitfield flag is bit 1");
    if (entries[5].is_bitfield == false) @compileError("bitfield flags report is_bitfield");

    if (!std.mem.eql(u8, entries[6].name, "EXTRA")) @compileError("a second marker's entries must append");
    if (entries[6].value != 5) @compileError("a second marker's values must be preserved");

    if (godot.annotations.findConstants(NoConstants).len != 0) @compileError("classes without a Constants marker must report none");
}

const NoConstants = struct {};

const HintMode = enum(i32) { idle, running = 3 };
const HintFlags = bitpack struct(u32) {
    first: bool = false,
    second: bool = false,
    _pad0: u30 = 0,
};

const LooseMode = enum(i32) { idle, running = 3 };
const LooseFlags = bitpack struct(u32) {
    first: bool = false,
    second: bool = false,
    _pad0: u30 = 0,
};

const OtherMode = enum(i32) { alpha, beta = 2 };
const OtherFlags = bitpack struct(u32) {
    other: bool = false,
    _pad0: u31 = 0,
};

/// An empty exhaustive enum is `noreturn`-backed and uninstantiable, so it
/// cannot be a `Property` value type; the null-hint edge cases that can be
/// expressed through a descriptor are the non-exhaustive enum and the bitpack
/// type without bool flag fields below.
const NonExhaustive = enum(u8) { a, _ };
const PaddingOnly = bitpack struct(u32) { _pad0: u32 = 0 };

/// Another class registers `OtherMode`/`OtherFlags`; a property using them must
/// get only the type-derived hint, never this class's registered metadata.
const OtherClass = struct {
    pub const Decl = godot.annotations.Constants(struct {
        pub const Other = OtherMode;
        pub const OtherFlagsDecl = OtherFlags;
    });
};

const HintOwner = struct {
    /// The declaration names differ from the Zig type names on purpose: the
    /// engine class-name qualifier must use the raw declaration name.
    pub const Decl = godot.annotations.Constants(struct {
        pub const ModeDecl = HintMode;
        pub const Flags = HintFlags;
    });

    registered_enum: godot.annotations.Property(HintMode, .{ .usage = .exported }) = .init(.idle),
    registered_flags: godot.annotations.Property(HintFlags, .{ .usage = .exported }) = .init(.{}),
    hidden_enum: godot.annotations.Property(HintMode, .{ .usage = .none }) = .init(.idle),
    unregistered_enum: godot.annotations.Property(LooseMode, .{ .usage = .exported }) = .init(.idle),
    unregistered_flags: godot.annotations.Property(LooseFlags, .{ .usage = .exported }) = .init(.{}),
    cross_class_enum: godot.annotations.Property(OtherMode, .{ .usage = .exported }) = .init(.alpha),
    cross_class_flags: godot.annotations.Property(OtherFlags, .{ .usage = .exported }) = .init(.{}),
    scalar: godot.annotations.Property(u32, .{ .usage = .exported }) = .init(0),
    non_exhaustive: godot.annotations.Property(NonExhaustive, .{ .usage = .exported }) = .init(.a),
    padding_only: godot.annotations.Property(PaddingOnly, .{ .usage = .exported }) = .init(.{}),
};

fn checkHintsThroughDescriptors() void {
    const descs = godot.annotations.property.descriptors(HintOwner);

    // Registered enum: type-derived enum hint plus same-class registered
    // class name and usage bit.
    if (descs[0].hint != .@"enum") @compileError("registered enum must get the enum hint");
    if (!std.mem.eql(u8, descs[0].hint_string, "Idle:0,Running:3")) @compileError(
        "enum hint strings are PascalCase labels with explicit values and no trailing comma",
    );
    if (!descs[0].usage.class_is_enum) @compileError("registered enum must set CLASS_IS_ENUM");
    if (descs[0].class_name == null or !std.mem.eql(u8, descs[0].class_name.?, "HintOwner.ModeDecl"))
        @compileError("registered enum class name must use the raw declaration name");

    // Registered bitfield: flags hint, masks from the bitpack layout, padding skipped.
    if (descs[1].hint != .flags) @compileError("registered bitfield must get the flags hint");
    if (!std.mem.eql(u8, descs[1].hint_string, "First:1,Second:2")) @compileError(
        "bitfield hint strings mask each flag bit and skip underscore-prefixed padding",
    );
    if (!descs[1].usage.class_is_bitfield) @compileError("registered bitfield must set CLASS_IS_BITFIELD");
    if (descs[1].class_name == null or !std.mem.eql(u8, descs[1].class_name.?, "HintOwner.Flags"))
        @compileError("registered bitfield class name must use the raw declaration name");

    // Hidden properties get no automatic hint or registered metadata.
    if (descs[2].hint != .none or descs[2].class_name != null) @compileError("hidden enum must stay hint-free");
    if (descs[2].usage.class_is_enum or descs[2].usage.class_is_bitfield) @compileError("hidden enum must stay unregistered");

    // Unregistered enum/bitfield: type-derived hint without a class name or bit.
    if (descs[3].hint != .@"enum") @compileError("unregistered enum must still get the enum hint");
    if (!std.mem.eql(u8, descs[3].hint_string, "Idle:0,Running:3")) @compileError("unregistered enum hint string");
    if (descs[3].class_name != null or descs[3].usage.class_is_enum) @compileError("unregistered enum must not claim a class name");
    if (descs[4].hint != .flags) @compileError("unregistered bitfield must still get the flags hint");
    if (!std.mem.eql(u8, descs[4].hint_string, "First:1,Second:2")) @compileError("unregistered bitfield hint string");
    if (descs[4].class_name != null or descs[4].usage.class_is_bitfield) @compileError("unregistered bitfield must not claim a class name");

    // Cross-class declarations: the hint applies, registered metadata belongs
    // to the declaring class and must not leak.
    if (descs[5].hint != .@"enum") @compileError("cross-class enum must get the enum hint");
    if (!std.mem.eql(u8, descs[5].hint_string, "Alpha:0,Beta:2")) @compileError("cross-class enum hint string");
    if (descs[5].class_name != null or descs[5].usage.class_is_enum) @compileError("cross-class enum must not claim this class's name");
    if (descs[6].hint != .flags) @compileError("cross-class bitfield must get the flags hint");
    if (!std.mem.eql(u8, descs[6].hint_string, "Other:1")) @compileError("cross-class bitfield hint string");
    if (descs[6].class_name != null or descs[6].usage.class_is_bitfield) @compileError("cross-class bitfield must not claim this class's name");

    // Types with no hintable entries: no hint, no hint string, no class name.
    if (descs[7].hint != .none or descs[7].hint_string.len != 0 or descs[7].class_name != null)
        @compileError("scalar must not get an inspector hint");
    if (descs[8].hint != .none or descs[8].class_name != null)
        @compileError("non-exhaustive enum must not emit a hint");
    if (descs[9].hint != .none or descs[9].class_name != null)
        @compileError("bitpack type without bool flag fields must not emit a hint");
}

comptime {
    checkConstantDiscovery();
    checkHintsThroughDescriptors();
}

test "constants are discovered in declaration order" {
    const entries = comptime godot.annotations.findConstants(ConstantsFixture);
    try std.testing.expectEqual(@as(usize, 7), entries.len);
    try std.testing.expectEqualStrings("MAX_HEALTH", entries[0].name);
    try std.testing.expectEqualStrings("RUNNING", entries[3].name);
    try std.testing.expectEqual(@as(i64, 2), entries[5].value);
    try std.testing.expectEqualStrings("EXTRA", entries[6].name);
}

test "bitfield bits come from the bitpack layout" {
    const Rear = struct {
        pub const Bits = godot.annotations.Constants(struct {
            pub const Flags = bitpack struct(u32) {
                _pad0: u2 = 0,
                third: bool = false,
                _pad1: u29 = 0,
            };
        });
    };
    const entries = comptime godot.annotations.findConstants(Rear);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(@as(i64, 4), entries[0].value);
}

const std = @import("std");

const godot = @import("godot");
