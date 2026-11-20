//! Annotation marker identity, used by field discovery.

/// The annotation family a wrapper type belongs to.
pub const Kind = enum {
    base,
    on_ready,
    property,
};

/// Returns the marker kind declared by wrapper type `F`, or null when `F` does
/// not declare one.
pub fn kindOf(comptime F: type) ?Kind {
    if (@typeInfo(F) != .@"struct") return null;
    if (!@hasDecl(F, "marker")) return null;
    if (@TypeOf(@field(F, "marker")) != Kind) return null;
    return @field(F, "marker");
}

/// True when `F` is an annotation wrapper declaring exactly `kind`.
pub fn is(comptime F: type, comptime kind: Kind) bool {
    const found = kindOf(F) orelse return false;
    return found == kind;
}
