// @struct StringName
pub fn fromComptimeLatin1(dispatcher: anytype, comptime str: [:0]const u8) StringName {
    const S = struct {
        const key = str;
        var value: StringName = undefined;
        var init: bool = false;
    };

    if (S.init) return S.value;

    dispatcher.dispatch(.string_name_new_with_latin1_chars, .{
        @as(interface.UninitializedStringNamePtr, @ptrCast(&S.value)),
        @as([*c]const u8, @ptrCast(str.ptr)),
        true,
    });
    S.init = true;

    return S.value;
}
// @struct_end StringName
