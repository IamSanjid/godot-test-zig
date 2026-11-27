//! Class-level ClassDB registration: a class's integer constants, signals, and
//! methods, run from the post-registration hook. See docs/classdb.md.

/// Runs class-level registration for one class. It is specialized per class and
/// erased to this shape so `RegisteredClass` can store it without knowing the
/// class type.
pub const PostRegistrationCallback = *const fn (
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void;

/// The post-registration callback for `T`, or null when `T` declares no
/// class-level metadata. The family list lives here because this module owns
/// the registration order.
pub fn postRegistrationCallback(comptime T: type) ?PostRegistrationCallback {
    if (comptime annotations.findMethods(T).len == 0 and
        annotations.findSignals(T).len == 0 and
        annotations.findConstants(T).len == 0) return null;

    return &struct {
        fn f(library: interface.ClassLibraryPtr, class_name: *const builtins.StringName) void {
            registerConstants(T, library, class_name);
            registerSignals(T, library, class_name);
            methods.registerMethods(T, library, class_name);
        }
    }.f;
}

fn registerConstants(
    comptime T: type,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    const entries = comptime annotations.findConstants(T);
    inline for (entries) |entry| registerConstant(entry, library, class_name);
}

fn registerConstant(
    comptime entry: annotations.ConstantEntry,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    // The engine copies both names during the call.
    const enum_name = builtins.StringName.fromLatin1(entry.enum_name, true);
    const constant_name = builtins.StringName.fromLatin1(entry.name, true);
    runtime.dispatch(.classdb_register_extension_class_integer_constant, .{
        library,
        class_name,
        &enum_name,
        &constant_name,
        entry.value,
        entry.is_bitfield,
    });
}

fn registerSignals(
    comptime T: type,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    const markers = comptime annotations.findSignals(T);
    inline for (markers) |marker| registerSignal(marker, library, class_name);
}

/// Registers one signal. The engine copies the argument metadata during the
/// call, so the arrays only need to live for its duration.
fn registerSignal(
    comptime marker: type,
    library: interface.ClassLibraryPtr,
    class_name: *const builtins.StringName,
) void {
    const argument_count = comptime marker.args.len;
    const signal_name = builtins.StringName.fromLatin1(marker.name, true);

    if (comptime argument_count == 0) {
        runtime.dispatch(.classdb_register_extension_class_signal, .{
            library,
            class_name,
            &signal_name,
            null,
            0,
        });
    } else {
        var argument_names: [argument_count]builtins.StringName = undefined;
        var class_names: [argument_count]builtins.StringName = undefined;
        var infos: [argument_count]interface.PropertyInfo = undefined;
        const hint_string = builtins.String.fromComptimeLatin1("");

        inline for (marker.args, 0..) |pair, index| {
            argument_names[index] = builtins.StringName.fromLatin1(pair[0], true);
            // The engine class name follows the converter's engine type, so a
            // custom type wrapping an object pointer exposes that class.
            class_names[index] = builtins.StringName.fromLatin1(
                conversion.engineClassName(pair[1]),
                true,
            );
            infos[index] = .{
                .type = signalArgumentType(marker.name, pair[0], pair[1]),
                .name = @as(interface.StringNamePtr, @ptrCast(&argument_names[index])),
                .class_name = @as(interface.StringNamePtr, @ptrCast(&class_names[index])),
                .hint = 0,
                .hint_string = @as(interface.StringPtr, @ptrCast(@constCast(&hint_string))),
                .usage = 0,
            };
        }

        runtime.dispatch(.classdb_register_extension_class_signal, .{
            library,
            class_name,
            &signal_name,
            &infos[0],
            @as(interface.Int, @intCast(argument_count)),
        });
    }
}

/// A `Variant` argument is `VariantType.nil` (an untyped value), not an error.
/// Every other declared Zig type must have a Variant conversion; its Variant
/// type is derived through the conversion layer.
fn signalArgumentType(
    comptime signal_name: [:0]const u8,
    comptime arg_name: [:0]const u8,
    comptime Value: type,
) interface.VariantType {
    if (comptime Value == builtins.Variant) return .nil;
    return comptime conversion.variantType(Value) orelse @compileError(std.fmt.comptimePrint(
        "Signal '{s}' argument '{s}': the Conversion marker reports Variant support for '{s}' but no Variant type; " ++
            "declare a custom Conversion marker for the type.",
        .{ signal_name, arg_name, @typeName(Value) },
    ));
}

const std = @import("std");

const bindings = @import("bindings");
const interface = bindings.interface;

const annotations = @import("../annotations/annotations.zig");
const builtins = @import("../builtins/builtins.zig");
const conversion = @import("../conversion.zig");
const runtime = @import("../runtime.zig");
const methods = @import("methods.zig");
