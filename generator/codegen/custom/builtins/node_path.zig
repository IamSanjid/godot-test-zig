// @section artifact fromComptimeLatin1

/// Creates a NodePath from a comptime Latin-1 encoded C string.
///
/// The result is cached for the lifetime of the process. NodePath copies the
/// parsed contents, so the temporary String is deinitialized immediately and
/// only the NodePath cache survives. Cached values must not be deinitialized.
pub fn fromComptimeLatin1(comptime str: [:0]const u8) NodePath {
    const NP = struct {
        const key = str;
        var value: NodePath = undefined;
        var init: bool = false;
    };

    if (NP.init) return NP.value;

    if (str.len == 0) {
        NP.value = NodePath.init();
    } else {
        var path = builtins.String.fromLatin1(str);
        defer path.deinit();
        NP.value = NodePath.fromString(path);
    }
    NP.init = true;

    return NP.value;
}
// @section_end artifact fromComptimeLatin1
