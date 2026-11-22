// @section artifact fromComptimeLatin1

/// Creates a StringName from a comptime Latin-1 encoded C string.
///
/// The string is treated as static and the result is cached per unique string.
pub fn fromComptimeLatin1(comptime str: [:0]const u8) StringName {
    const SN = struct {
        // Keeps the cache per comptime string; without it they all share one.
        const key = str;
        var value: StringName = undefined;
        var init: bool = false;
    };

    if (SN.init) return SN.value;

    runtime.dispatch(.string_name_new_with_latin1_chars, .{
        @as(bindings.interface.UninitializedStringNamePtr, @ptrCast(&SN.value)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        true,
    });
    SN.init = true;

    return SN.value;
}
// @section_end artifact fromComptimeLatin1

// @section artifact fromLatin1

/// Creates a StringName from a Latin-1 encoded C string.
pub inline fn fromLatin1(str: [:0]const u8, is_static: bool) StringName {
    var result: StringName = undefined;
    runtime.dispatch(.string_name_new_with_latin1_chars, .{
        @as(bindings.interface.UninitializedStringNamePtr, @ptrCast(&result)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        is_static,
    });
    return result;
}
// @section_end artifact fromLatin1

// @section artifact fromUtf8

/// Creates a StringName from a UTF-8 encoded string.
pub inline fn fromUtf8(str: []const u8) StringName {
    var result: StringName = undefined;
    runtime.dispatch(.string_name_new_with_utf8_chars_and_len, .{
        @as(bindings.interface.UninitializedStringNamePtr, @ptrCast(&result)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        @intCast(str.len),
    });
    return result;
}
// @section_end artifact fromUtf8

// @section artifact fromType

/// Uses the canonical `GodotClassName` / extension class name.
pub fn fromType(comptime T: type) StringName {
    return fromComptimeLatin1(runtime.reflect.className(T));
}
// @section_end artifact fromType

// @section artifact fromTypeName

/// Pascal-converts a name without a generated `GodotClassName` annotation.
/// Prefer `fromType` when the type is known.
pub fn fromTypeName(comptime name: []const u8) StringName {
    const converted = comptime naming.comptimeConvert(.godot, .type, name);
    return fromComptimeLatin1(converted);
}
// @section_end artifact fromTypeName

// @section file
const naming = @import("naming");
// @section_end file
