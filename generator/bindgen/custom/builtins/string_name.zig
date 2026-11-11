// @struct StringName
/// Creates a StringName from a comptime Latin-1 encoded C string.
///
/// The string is treated as static and the result is cached per unique string.
pub fn fromComptimeLatin1(dispatcher: anytype, comptime str: [:0]const u8) StringName {
    const SN = struct {
        const key = str;
        var value: StringName = undefined;
        var init: bool = false;
    };

    if (SN.init) return SN.value;

    dispatcher.dispatch(.string_name_new_with_latin1_chars, .{
        @as(interface.UninitializedStringNamePtr, @ptrCast(&SN.value)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        true,
    });
    SN.init = true;

    return SN.value;
}

/// Creates a StringName from a UTF-8 encoded string.
pub inline fn fromUtf8(dispatcher: anytype, str: []const u8) StringName {
    var result: StringName = undefined;
    dispatcher.dispatch(.string_name_new_with_utf8_chars_and_len, .{
        @as(interface.UninitializedStringNamePtr, @ptrCast(&result)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        @intCast(str.len),
    });
    return result;
}
// @struct_end StringName
