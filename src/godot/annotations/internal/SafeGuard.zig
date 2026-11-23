state: Guard = if (is_safe_mode) Guard.init(unset) else {},

const Self = @This();
const unset = 0;
const setting = 1;
const ready = 2;
const Guard = if (is_safe_mode) std.atomic.Value(usize) else void;

pub inline fn getGuard(
    self: *const Self,
    comptime RetT: type,
    comptime getFn: anytype,
    args: anytype,
) RetT {
    if (comptime is_safe_mode) assert(self.state.load(.acquire) == ready);
    return @call(.always_inline, getFn, args);
}

pub inline fn setGuard(
    self: *Self,
    comptime setFn: anytype,
    args: anytype,
) void {
    if (comptime is_safe_mode) {
        // null == swap succeeded; anything else is the value that was already there
        assert(self.state.cmpxchgStrong(unset, setting, .acquire, .monotonic) == null);
    }
    @call(.always_inline, setFn, args);
    if (comptime is_safe_mode) self.state.store(ready, .release);
}

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const is_safe_mode = builtin.mode.runtimeSafety();
