//! Annotation marker identity for field wrappers and declaration/type markers.
//! Identity is checked first; family shape validation still runs separately.

/// The annotation family an annotation type belongs to.
pub const Kind = enum {
    base,
    on_ready,
    property,
    init_callback,
    deinit_callback,
    notification_callback,
    signal,
    constants,
    property_groups,
    conversion,
    override,
};

/// Returns the marker kind declared by annotation type `F`, or null when `F`
/// does not declare one.
pub fn kindOf(comptime F: type) ?Kind {
    if (@typeInfo(F) != .@"struct") return null;
    if (!@hasDecl(F, "marker")) return null;
    if (@TypeOf(@field(F, "marker")) != Kind) return null;
    return @field(F, "marker");
}

/// True when `F` is an annotation type declaring exactly `kind`.
pub fn is(comptime F: type, comptime kind: Kind) bool {
    const found = kindOf(F) orelse return false;
    return found == kind;
}
