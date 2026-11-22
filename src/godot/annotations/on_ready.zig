/// Field resolved after the node enters the tree (before `_ready`), or on a
/// hot-reload notification when it is already inside the tree.
pub fn OnReady(comptime T: type) type {
    const ValueT = if (reflect.isEngineObjectClass(T)) *T else T;
    return struct {
        /// `func` returns `ValueT`/`?ValueT`; `args` uses `Init` placeholders.
        pub fn Call(comptime func: anytype, comptime args: anytype) type {
            return struct {
                pub const ForT = T;
                pub const InitCall = init_mod.Init(?ValueT, func, args);
                pub const marker = marker_mod.Kind.on_ready;

                value: ?ValueT = null,

                const Self = @This();

                pub fn init(comptime OwnerT: type, comptime Base: type, owner: *OwnerT, base: *Base) Self {
                    return .{ .value = InitCall.call(OwnerT, Base, owner, base) };
                }

                pub fn get(self: *const Self) ValueT {
                    return self.value orelse if (is_runtime_safety)
                        @panic("OnReady<" ++ @typeName(T) ++ "> used before _ready or its init failed")
                    else
                        unreachable;
                }

                pub fn getPtr(self: *Self) ?*ValueT {
                    if (self.value) |*v| return v;
                    return null;
                }

                pub fn getPtrConst(self: *const Self) ?*const ValueT {
                    if (self.value) |*v| return v;
                    return null;
                }
            };
        }

        pub fn Node(comptime node_path: [:0]const u8) type {
            return Call(struct {
                // TODO: Should we keep accepting as *anyopaque? Find better way to determine the type maybe?
                fn init(base_ptr: *anyopaque) ?ValueT {
                    const base: *classes.core.Node = @ptrCast(@alignCast(base_ptr));
                    const value = if (base.getNode(.fromComptimeLatin1(node_path))) |v| v.downcast(T) else null;
                    return value;
                }
            }.init, .{.base});
        }
    };
}

pub fn initOnReadyFields(comptime T: type, comptime B: type, owner: *T, base: *B) void {
    inline for (comptime findOnReadyFieldNames(T)) |field| {
        @field(owner, field) = .init(T, B, owner, base);
    }
}

/// Finds `OnReady` fields declared directly on `T`.
pub fn findOnReadyFieldNames(comptime T: type) []const [:0]const u8 {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") @compileError("Expected struct, found: " ++ @typeName(T));
        const info = type_info.@"struct";
        var names: [info.field_names.len][:0]const u8 = undefined;
        var n: usize = 0;
        for (info.field_names, info.field_types) |name, F| {
            if (!reflect.isNormalStruct(F)) continue;
            if (!marker_mod.is(F, .on_ready)) continue;
            if (!isOnReady(F)) continue;
            names[n] = name;
            n += 1;
        }
        const out = names[0..n].*;
        return &out;
    }
}

pub fn isOnReady(OtherT: type) bool {
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "ForT") or
        !@hasDecl(OtherT, "InitCall")) return false;
    if (@TypeOf(OtherT.marker) != marker_mod.Kind) return false;
    return OtherT.marker == .on_ready;
}

// Compile-only: a lookalike without the marker is not OnReady.

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
    child: OnReady(classes.core.Node).Node("./ChildNode"),
    computed: OnReady(u32).Call(five, .{}),
    lookalike: Lookalike = .{},
};

fn checkOnReadyDiscovery() void {
    const names = findOnReadyFieldNames(DiscoveryOwner);
    if (names.len != 2) @compileError("OnReady discovery must find exactly the marker-declaring fields");
    if (!std.mem.eql(u8, names[0], "child")) @compileError("OnReady discovery found the wrong field (1)");
    if (!std.mem.eql(u8, names[1], "computed")) @compileError("OnReady discovery found the wrong field (2)");
    if (!marker_mod.is(@FieldType(DiscoveryOwner, "child"), .on_ready))
        @compileError("OnReadyNode wrappers must declare marker.Kind.on_ready");
    if (!marker_mod.is(@FieldType(DiscoveryOwner, "computed"), .on_ready))
        @compileError("OnReadyCall wrappers must declare marker.Kind.on_ready");
    if (marker_mod.kindOf(Lookalike) != null) @compileError("a lookalike must not declare an annotation marker");
    if (findOnReadyFieldNames(Lookalike).len != 0) @compileError("a lookalike must not be discovered as OnReady");
    if (findOnReadyFieldNames(DiscoveryOwner).len != 2) @compileError("discovery must stay stable");
}

comptime {
    checkOnReadyDiscovery();
}

test "marker-keyed OnReady discovery" {
    comptime checkOnReadyDiscovery();
}

const std = @import("std");
const is_runtime_safety = @import("builtin").mode.runtimeSafety();

const reflect = @import("../reflect/reflect.zig");
const classes = @import("../classes/classes.zig");
const marker_mod = @import("marker.zig");

const init_mod = @import("init.zig");
