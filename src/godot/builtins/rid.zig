//! Pure-Zig implementation of Godot's `RID` handle builtin.
//!
//! A `RID` is an opaque 64-bit engine handle. Only validity and integer-id
//! conversion belong to the math layer; ownership lives in the engine. The
//! layout is precision-independent, so this file defines the struct directly.

pub const RID = extern struct {
    pub const GodotClassName = "RID";

    id: u64 align(@alignOf(bindings.builtins.RID)) = 0,

    const Self = @This();

    pub inline fn toBinding(self: *const Self) bindings.builtins.RID {
        return @as(*const bindings.builtins.RID, @ptrCast(self)).*;
    }

    pub inline fn fromBinding(v: anytype) Self {
        const V = @TypeOf(v);
        return switch (V) {
            *bindings.builtins.RID => @as(*const Self, @ptrCast(v)).*,
            *const bindings.builtins.RID => @as(*const Self, @ptrCast(v)).*,
            bindings.builtins.RID => @as(*const Self, @ptrCast(&v)).*,
            else => @compileError("Expected bindings.builtins.RID by value or a pointer to it, found: " ++ @typeName(V)),
        };
    }

    pub inline fn bindingCall(
        self: *Self,
        comptime method: @EnumLiteral(),
        args: reflect.FunctionArgsAsTupleSkipFirst(reflect.FunctionOf(generated_namespace.MemberFunctions, method)),
    ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
        const func = reflect.FunctionOf(generated_namespace, method);
        return @call(.auto, func, .{self} ++ args);
    }

    pub inline fn bindingCallConst(
        self: *const Self,
        comptime method: @EnumLiteral(),
        args: reflect.FunctionArgsAsTupleSkipFirst(reflect.FunctionOf(generated_namespace.MemberFunctions, method)),
    ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
        const func = reflect.FunctionOf(generated_namespace, method);
        return @call(.auto, func, .{self} ++ args);
    }

    pub inline fn bindingCallStatic(
        comptime method: @EnumLiteral(),
        args: reflect.FunctionArgsAsTuple(reflect.FunctionOf(generated_namespace.StaticFunctions, method)),
    ) reflect.FunctionReturnType(reflect.FunctionOf(generated_namespace, method)) {
        const func = reflect.FunctionOf(generated_namespace, method);
        return @call(.auto, func, args);
    }

    pub fn init(id: u64) Self {
        return .{ .id = id };
    }

    pub fn fromUint64(id: u64) Self {
        return .{ .id = id };
    }

    pub fn isValid(self: Self) bool {
        return self.id != 0;
    }

    pub fn getId(self: Self) u64 {
        return self.id;
    }
};

const bindings = @import("bindings");

const reflect = @import("../reflect/reflect.zig");
const generated_namespace = @import("generated/rid.zig");
