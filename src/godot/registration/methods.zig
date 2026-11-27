//! Method registration: ClassDB method metadata and the engine-facing
//! `call_func`/`ptrcall_func` adapters for `Method` declarations.
//!
//! Method arguments are call-scoped: the adapters release every decoded value
//! after the call, so an implementation must not store or deinitialize one.
//! Results are outgoing values, never the argument decodes. A raw object
//! pointer result is borrowed: return `?*T` for an object owned elsewhere. An
//! owned `RefCounted` result is declared as `ownership.Ref(T)`, so the adapter
//! releases the returned wrapper after the engine keeps its own reference.
//! See docs/classdb.md.

/// The two engine adapters built for one resolved method entry.
pub const Callbacks = struct {
    call_func: interface.ClassMethodCall,
    ptrcall_func: interface.ClassMethodPtrCall,
};

/// Registers every method declared by `T`.
///
/// `StringName` construction and dispatch need an initialized engine. The
/// engine copies the method name and the metadata tables during the
/// registration call, so all storage here is call-scoped and nothing is
/// allocated.
pub fn registerMethods(
    comptime T: type,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    const entries = comptime annotations.findMethods(T);
    inline for (entries) |Entry| registerMethod(Entry, library, class_name);
}

/// Builds both engine adapters for one `findMethods` entry type.
///
/// The adapters are non-capturing: the class instance arrives as
/// `p_instance`, so `method_userdata` stays null.
pub fn callbacks(comptime Entry: type) Callbacks {
    return .{
        .call_func = makeCallFunc(Entry),
        .ptrcall_func = makePtrCallFunc(Entry),
    };
}

/// Engine `GDExtensionClassMethodFlags` bits for one resolved entry: the
/// default normal-method flags plus `const` and `static`.
pub fn methodFlags(comptime Entry: type) u32 {
    var flags: interface.ClassMethodFlags = .default;
    flags.@"const" = Entry.is_const;
    flags.static = Entry.is_static;
    return @bitCast(flags);
}

fn registerMethod(
    comptime Entry: type,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    const function = @typeInfo(Entry.Fn).@"fn";
    const offset = comptime engineArgumentOffset(Entry);
    const argument_count = function.param_types.len - offset;
    const Return = function.return_type orelse void;

    const method_name = builtins.StringName.fromLatin1(Entry.name, true);
    const hint_string = builtins.String.fromComptimeLatin1("");

    var argument_names: [argument_count]builtins.StringName = undefined;
    var argument_class_names: [argument_count]builtins.StringName = undefined;
    var argument_infos: [argument_count]interface.PropertyInfo = undefined;
    var argument_metadata: [argument_count]interface.ClassMethodArgumentMetadata = undefined;
    inline for (0..argument_count) |index| {
        const Param = function.param_types[offset + index].?;
        argument_names[index] = builtins.StringName.fromLatin1(Entry.argName(index), true);
        argument_class_names[index] =
            builtins.StringName.fromLatin1(registeredClassName(Param), true);
        argument_metadata[index] = .none;
        argument_infos[index] = .{
            .type = registeredVariantType(Param),
            .name = @as(interface.StringNamePtr, @ptrCast(&argument_names[index])),
            .class_name = @as(interface.StringNamePtr, @ptrCast(&argument_class_names[index])),
            .hint = 0,
            .hint_string = @as(interface.StringPtr, @ptrCast(@constCast(&hint_string))),
            .usage = comptime valueUsage(Param),
        };
    }

    // The engine reads the return fields only when `has_return_value` is set; a
    // return-less method still gets valid storage so the field can stay null.
    const return_name = builtins.StringName.fromComptimeLatin1("");
    const return_class_name =
        builtins.StringName.fromComptimeLatin1(comptime registeredClassName(Return));
    const return_info: interface.PropertyInfo = .{
        .type = registeredVariantType(Return),
        .name = @as(interface.StringNamePtr, @ptrCast(@constCast(&return_name))),
        .class_name = @as(interface.StringNamePtr, @ptrCast(@constCast(&return_class_name))),
        .hint = 0,
        .hint_string = @as(interface.StringPtr, @ptrCast(@constCast(&hint_string))),
        .usage = comptime valueUsage(Return),
    };
    const return_info_ptr: ?*interface.PropertyInfo = if (comptime Return == void)
        null
    else
        @ptrCast(@constCast(&return_info));

    const adapters = callbacks(Entry);
    const method_info: interface.ClassMethodInfo = .{
        .name = @as(interface.StringNamePtr, @ptrCast(@constCast(&method_name))),
        .method_userdata = null,
        .call_func = adapters.call_func,
        .ptrcall_func = adapters.ptrcall_func,
        .method_flags = methodFlags(Entry),
        .has_return_value = comptime Return != void,
        .return_value_info = return_info_ptr,
        .return_value_metadata = .none,
        .argument_count = @intCast(argument_count),
        .arguments_info = if (argument_count == 0)
            null
        else
            @as(?*interface.PropertyInfo, @ptrCast(&argument_infos)),
        .arguments_metadata = if (argument_count == 0)
            null
        else
            @as([*c]interface.ClassMethodArgumentMetadata, @ptrCast(&argument_metadata)),
        .default_argument_count = 0,
        .default_arguments = null,
    };

    runtime.dispatch(.classdb_register_extension_class_method, .{
        library,
        class_name,
        &method_info,
    });
}

fn makeCallFunc(comptime Entry: type) interface.ClassMethodCall {
    return &struct {
        fn call(
            _: ?*anyopaque,
            p_instance: interface.ClassInstancePtr,
            p_args: [*c]const interface.ConstVariantPtr,
            p_argument_count: interface.Int,
            r_return: interface.VariantPtr,
            r_error: ?*interface.CallError,
        ) callconv(.c) void {
            const function = @typeInfo(Entry.Fn).@"fn";
            const offset = comptime engineArgumentOffset(Entry);
            const argument_count = function.param_types.len - offset;
            const Return = function.return_type orelse void;

            const return_variant: ?*builtins.Variant = if (r_return) |raw|
                @ptrCast(@alignCast(raw))
            else
                null;
            if (return_variant) |out| out.* = builtins.Variant.nil;

            if (p_argument_count < @as(interface.Int, @intCast(argument_count))) {
                setCallError(r_error, .too_few_arguments, -1, @intCast(argument_count));
                return;
            }
            if (p_argument_count > @as(interface.Int, @intCast(argument_count))) {
                setCallError(r_error, .too_many_arguments, -1, @intCast(argument_count));
                return;
            }

            var args: std.meta.ArgsTuple(Entry.Fn) = undefined;
            if (comptime !Entry.is_static) {
                args[0] = @ptrCast(@alignCast(p_instance orelse {
                    setCallError(r_error, .instance_is_null, -1, 0);
                    return;
                }));
            }

            // Arguments decoded before a later mismatch must still be released.
            var present: [argument_count]bool = @splat(false);
            defer {
                inline for (0..argument_count) |index| {
                    if (present[index]) {
                        const Param = function.param_types[offset + index].?;
                        conversion.deinitDecodedArgument(Param, .variant, &args[offset + index]);
                    }
                }
            }

            inline for (0..argument_count) |index| {
                const Param = function.param_types[offset + index].?;
                const raw_argument = p_args[index] orelse {
                    setCallError(
                        r_error,
                        .invalid_argument,
                        @intCast(index),
                        @intCast(@backingInt(registeredVariantType(Param))),
                    );
                    return;
                };
                const argument: *const builtins.Variant = @ptrCast(@alignCast(raw_argument));
                args[offset + index] = conversion.decodeVariant(Param, argument) orelse {
                    setCallError(
                        r_error,
                        .invalid_argument,
                        @intCast(index),
                        @intCast(@backingInt(registeredVariantType(Param))),
                    );
                    return;
                };
                present[index] = true;
            }

            if (comptime Return == void) {
                _ = @call(.auto, Entry.implementation, args);
            } else {
                var result = @call(.auto, Entry.implementation, args);
                // The Variant owns its copy after `encodeVariant`.
                defer conversion.deinitDecodedArgument(Return, .variant, &result);
                if (return_variant) |out| conversion.encodeVariant(Return, result, out);
            }
        }
    }.call;
}

fn makePtrCallFunc(comptime Entry: type) interface.ClassMethodPtrCall {
    return &struct {
        fn call(
            _: ?*anyopaque,
            p_instance: interface.ClassInstancePtr,
            p_args: [*c]const interface.ConstTypePtr,
            r_ret: interface.TypePtr,
        ) callconv(.c) void {
            const function = @typeInfo(Entry.Fn).@"fn";
            const offset = comptime engineArgumentOffset(Entry);
            const argument_count = function.param_types.len - offset;
            const Return = function.return_type orelse void;

            var args: std.meta.ArgsTuple(Entry.Fn) = undefined;
            if (comptime !Entry.is_static) {
                args[0] = @ptrCast(@alignCast(p_instance));
            }

            inline for (0..argument_count) |index| {
                const Param = function.param_types[offset + index].?;
                args[offset + index] = conversion.decodePtrcallSlot(Param, p_args[index]);
            }

            defer {
                inline for (0..argument_count) |index| {
                    const Param = function.param_types[offset + index].?;
                    conversion.deinitDecodedArgument(Param, .ptrcall, &args[offset + index]);
                }
            }

            if (comptime Return == void) {
                _ = @call(.auto, Entry.implementation, args);
            } else {
                var result = @call(.auto, Entry.implementation, args);
                defer conversion.deinitDecodedArgument(Return, .ptrcall, &result);
                conversion.encodePtrcallSlot(Return, result, r_ret);
            }
        }
    }.call;
}

/// Number of parameters before the engine arguments: the self parameter is
/// present exactly for instance methods.
fn engineArgumentOffset(comptime Entry: type) usize {
    return if (Entry.is_static) 0 else 1;
}

fn setCallError(
    r_error: ?*interface.CallError,
    error_type: interface.CallErrorType,
    argument: i32,
    expected: i32,
) void {
    const out = r_error orelse return;
    out.* = .{
        .@"error" = error_type,
        .argument = argument,
        .expected = expected,
    };
}

/// Variant type registered for one engine value. `Variant` is untyped (`.nil`),
/// and `void` has no metadata but still reports an untyped result.
fn registeredVariantType(comptime Value: type) interface.VariantType {
    if (comptime Value == void or Value == builtins.Variant) return .nil;
    return comptime conversion.variantType(Value) orelse @compileError(std.fmt.comptimePrint(
        "Method value type '{s}' has Variant support but no Variant type; " ++
            "declare a custom Conversion marker for it.",
        .{@typeName(Value)},
    ));
}

/// Extra `PropertyInfo.usage` flag for one engine value: GDScript needs
/// `PROPERTY_USAGE_NIL_IS_VARIANT` to treat an untyped Variant slot as Variant,
/// not void. Other types leave the usage empty.
fn valueUsage(comptime Value: type) u32 {
    if (comptime Value == builtins.Variant) {
        const usage: enums.PropertyUsageFlags = .{ .nil_is_variant = true };
        return @bitCast(usage);
    }
    return 0;
}

/// Engine class name registered for one engine value, or empty for non-objects
/// and return-less methods.
fn registeredClassName(comptime Value: type) [:0]const u8 {
    if (comptime Value == void) return "";
    return comptime conversion.engineClassName(Value);
}

const std = @import("std");

const bindings = @import("bindings");
const enums = bindings.enums;
const interface = bindings.interface;

const annotations = @import("../annotations/annotations.zig");
const builtins = @import("../builtins/builtins.zig");
const conversion = @import("../conversion.zig");
const runtime = @import("../runtime.zig");
