// @section artifact fromComptimeLatin1
/// Creates a String from a comptime Latin-1 encoded C string.
///
/// String has no static-buffer constructor, so this copies once and caches the
/// result for the lifetime of the process. Do not deinitialize cached values.
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

// @section_end artifact fromComptimeLatin1
// @section artifact fromLatin1
/// Creates a String from a Latin-1 encoded C string.
pub inline fn fromLatin1(dispatcher: anytype, str: []const u8) String {
    var result: String = undefined;
    dispatcher.dispatch(.string_new_with_latin1_chars_and_len, .{
        @as(interface.UninitializedStringPtr, @ptrCast(&result)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        @intCast(str.len),
    });
    return result;
}

// @section_end artifact fromLatin1
// @section artifact fromUtf8
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
// @section_end artifact fromUtf8
