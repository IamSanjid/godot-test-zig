// @struct String
/// Creates a String from a comptime Latin-1 encoded C string.
///
/// The string is treated as static and the result is cached per unique string.
pub fn fromComptimeLatin1(dispatcher: anytype, comptime str: [:0]const u8) String {
    const S = struct {
        const key = str;
        var value: String = undefined;
        var init: bool = false;
    };

    if (S.init) return S.value;

    dispatcher.dispatch(.string_new_with_latin1_chars, .{
        @as(interface.UninitializedStringPtr, @ptrCast(&S.value)),
        @as([*c]const u8, @ptrCast(str.ptr)),
    });
    S.init = true;

    return S.value;
}

/// Creates a String from a UTF-8 encoded C string with the given length.
pub inline fn fromUtf8(dispatcher: anytype, str: []const u8) !String {
    var result: String = undefined;
    const err = dispatcher.dispatch(.string_new_with_utf8_chars_and_len2, .{
        @as(interface.UninitializedStringPtr, @ptrCast(&result)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        @intCast(str.len),
    });
    if (err != 0) return error.FailedToCreateString;
    return result;
}
// @struct_end String
