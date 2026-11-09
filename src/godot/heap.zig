pub const engine_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = &alloc,
        .resize = &resize,
        .remap = &remap,
        .free = &free,
    },
};

const pad_align = @import("builtin").mode == .debug;

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    if (alignment == .@"1") {
        return @ptrCast(godot.dispatch(.mem_alloc2, .{ len, pad_align }) orelse return null);
    }

    const padding = @sizeOf(u32) + alignment.toByteUnits() - 1;
    const unaligned_ptr = godot.dispatch(.mem_alloc2, .{ len + padding, pad_align }) orelse return null;
    const unaligned_addr = @intFromPtr(unaligned_ptr);
    const aligned_addr = alignment.forward(unaligned_addr + @sizeOf(u32));

    @as(*align(1) u32, @ptrFromInt(aligned_addr - @sizeOf(u32))).* = @intCast(aligned_addr - unaligned_addr);

    return @ptrFromInt(aligned_addr);
}

fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
    return false;
}

fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
    if (alignment == .@"1") {
        return @ptrCast(godot.dispatch(.mem_realloc2, .{ memory.ptr, new_len, pad_align }) orelse return null);
    }

    const padding = @sizeOf(u32) + alignment.toByteUnits() - 1;
    const aligned_addr = @intFromPtr(memory.ptr);
    const old_payload_offset = @as(*align(1) u32, @ptrFromInt(aligned_addr - @sizeOf(u32))).*;
    const old_unaligned_addr = aligned_addr - old_payload_offset;
    const old_unaligned_ptr: [*]u8 = @ptrFromInt(old_unaligned_addr);

    const new_unaligned_ptr = godot.dispatch(.mem_realloc2, .{ old_unaligned_ptr, new_len + padding, pad_align }) orelse return null;
    const new_unaligned_addr = @intFromPtr(new_unaligned_ptr);
    const new_aligned_addr = alignment.forward(new_unaligned_addr + @sizeOf(u32));
    const new_payload_offset = new_aligned_addr - new_unaligned_addr;

    // Raw realloc preserves the raw prefix, leaving the payload at its old offset.
    // Move it before new metadata can overwrite any of those bytes.
    if (old_payload_offset != new_payload_offset) {
        const preserved_len = @min(memory.len, new_len);
        const source: [*]const u8 = @ptrFromInt(new_unaligned_addr + old_payload_offset);
        const destination: [*]u8 = @ptrFromInt(new_aligned_addr);
        @memmove(destination[0..preserved_len], source[0..preserved_len]);
    }

    @as(*align(1) u32, @ptrFromInt(new_aligned_addr - @sizeOf(u32))).* = @intCast(new_payload_offset);

    return @ptrFromInt(new_aligned_addr);
}

fn free(_: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
    if (alignment == .@"1") {
        godot.dispatch(.mem_free2, .{ memory.ptr, pad_align });
        return;
    }

    const aligned_addr = @intFromPtr(memory.ptr);
    const offset = @as(*align(1) u32, @ptrFromInt(aligned_addr - @sizeOf(u32))).*;

    godot.dispatch(.mem_free2, .{ @ptrFromInt(aligned_addr - offset), pad_align });
}

const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

const godot = @import("godot.zig");
