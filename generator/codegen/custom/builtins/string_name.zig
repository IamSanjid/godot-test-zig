// @method fromComptimeLatin1

/// Creates a StringName from a comptime Latin-1 encoded C string.
///
/// The string is treated as static and the result is cached per unique string.
pub fn fromComptimeLatin1(comptime str: [:0]const u8) StringName {
    const SN = struct {
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
// @method_end fromComptimeLatin1

// @method fromUtf8

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
// @method_end fromUtf8

// @method fromType

/// Uses the generated `GodotClassName` when available; otherwise falls back to
/// Pascal conversion of the short Zig type name.
pub fn fromType(comptime T: type) StringName {
    if (@hasDecl(T, "GodotClassName")) {
        return fromComptimeLatin1(T.GodotClassName);
    }
    return fromTypeName(typeShortName(T));
}
// @method_end fromType

// @method fromUserType

/// Uses the user type's short name verbatim. No case conversion is applied.
pub fn fromUserType(comptime T: type) StringName {
    return fromComptimeLatin1(typeShortName(T));
}
// @method_end fromUserType

// @method fromTypeName

/// Pascal-converts a name without a generated `GodotClassName` annotation.
/// Prefer `fromType` or `fromUserType` when the type is known.
pub fn fromTypeName(comptime name: []const u8) StringName {
    const converted = comptime naming.comptimeConvert(.godot, .type, name);
    return fromComptimeLatin1(converted);
}
// @method_end fromTypeName

// @method typeShortName

fn typeShortName(comptime T: type) [:0]const u8 {
    const full = @typeName(T);
    const pos = std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
    return full[pos + 1 ..];
}
// @method_end typeShortName

// @imports
const naming = @import("naming");
// @imports_end
