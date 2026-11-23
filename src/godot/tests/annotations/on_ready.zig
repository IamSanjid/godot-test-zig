//! `OnReady` marker-keyed field discovery.

/// A lookalike without the marker is not OnReady.
const Lookalike = struct {
    value: u32 = 0,

    pub fn isSelf(OtherT: type) bool {
        return OtherT == Lookalike;
    }
};

fn five() u32 {
    return 5;
}

const DiscoveryOwner = struct {
    value: u32 = 0,
    child: godot.annotations.OnReady(godot.classes.core.Node).Node("./ChildNode"),
    computed: godot.annotations.OnReady(u32).Call(five, .{}),
    lookalike: Lookalike = .{},
};

fn checkOnReadyDiscovery() void {
    const names = godot.annotations.findOnReadyFieldNames(DiscoveryOwner);
    if (names.len != 2) @compileError("OnReady discovery must find exactly the marker-declaring fields");
    if (!std.mem.eql(u8, names[0], "child")) @compileError("OnReady discovery found the wrong field (1)");
    if (!std.mem.eql(u8, names[1], "computed")) @compileError("OnReady discovery found the wrong field (2)");
    if (!godot.annotations.marker.is(@FieldType(DiscoveryOwner, "child"), .on_ready))
        @compileError("OnReadyNode wrappers must declare marker.Kind.on_ready");
    if (!godot.annotations.marker.is(@FieldType(DiscoveryOwner, "computed"), .on_ready))
        @compileError("OnReadyCall wrappers must declare marker.Kind.on_ready");
    if (godot.annotations.marker.kindOf(Lookalike) != null)
        @compileError("a lookalike must not declare an annotation marker");
    if (godot.annotations.findOnReadyFieldNames(Lookalike).len != 0)
        @compileError("a lookalike must not be discovered as OnReady");
    if (godot.annotations.findOnReadyFieldNames(DiscoveryOwner).len != 2)
        @compileError("discovery must stay stable");
}

comptime {
    checkOnReadyDiscovery();
}

test "marker-keyed OnReady discovery" {
    comptime checkOnReadyDiscovery();
}

const std = @import("std");

const godot = @import("godot");
