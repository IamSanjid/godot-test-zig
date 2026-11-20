/// Initializes ordinary Zig field defaults after `allocator.create`.
pub fn initFieldsDefault(comptime T: type, child: *T) void {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("Expected struct, found: " ++ @typeName(T));
    const struct_info = type_info.@"struct";
    inline for (struct_info.field_names, struct_info.field_attrs, struct_info.field_types) |field, attr, F| {
        if (comptime attr.default_value_ptr != null) {
            @field(child, field) = attr.defaultValue(F) orelse unreachable;
        }
    }
}
