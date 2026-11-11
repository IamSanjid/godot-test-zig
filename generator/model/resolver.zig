//! Class metadata index, inheritance chain, and API type resolution.

pub const Scope = enum {
    class_file,
    builtin_file,
    utility_file,
    native_file,
};

pub const TypeContext = enum {
    argument,
    return_value,
};

pub const TypeKind = enum {
    primitive,
    builtin,
    class_ptr,
    native_ptr,
    @"enum",
    variant,
    void,
};

pub const ResolvedType = struct {
    kind: TypeKind,
    zig: []const u8,
    /// Class whose module must be imported, if any.
    import_class: ?[]const u8 = null,
    import_native: bool = false,
    import_enums: bool = false,
    use_classes: bool = false,
    is_bitfield: bool = false,
    bitfield_bits: u8 = 32,
};

pub const Info = struct {
    class: *const ExtensionApiJson.Class,
    base: ?usize = null,
    virtual_names: []const VirtualName = &.{},
};

pub const VirtualName = struct {
    raw: []const u8,
    zig: []const u8,
};

const Rename = struct {
    name: []const u8,
    alias: []const u8,
};

pub const ClassResolver = struct {
    api: ExtensionApiJson,
    arena: Allocator,
    infos: []Info,
    builtin_classes: []const ExtensionApiJson.BuiltinClass,
    real_type: []const u8,
    renames: []const Rename,
    builtin_names: []const []const u8,

    pub fn init(arena: Allocator, api: ExtensionApiJson, real_type: []const u8, builtin_names: []const []const u8) !ClassResolver {
        const infos = try arena.alloc(Info, api.classes.len);
        for (api.classes, 0..) |class, index| {
            const class_copy = try arena.create(ExtensionApiJson.Class);
            class_copy.* = class;

            const methods = try arena.alloc(ExtensionApiJson.ClassMethod, class.methods.len);
            for (class.methods, 0..) |method, method_index| {
                methods[method_index] = method;
            }
            for (methods) |*method| {
                const description = method.description orelse continue;
                if (method.arguments.len == 0) continue;
                const arguments = try arena.alloc(ExtensionApiJson.Argument, method.arguments.len);
                for (method.arguments, 0..) |argument, argument_index| {
                    arguments[argument_index] = argument;
                }
                for (arguments) |*argument| {
                    if (try inferEnumArgument(arena, api, class_copy, argument, description)) |inferred| {
                        argument.type = inferred;
                    }
                }
                method.arguments = arguments;
            }
            class_copy.methods = methods;
            infos[index] = .{ .class = class_copy };
        }
        std.mem.sort(Info, infos, {}, lessThanInfo);

        for (infos) |*info| {
            if (info.class.inherits) |base_name| {
                info.base = indexOf(infos, base_name);
            }
        }
        for (infos) |*info| {
            info.virtual_names = try buildVirtualNames(arena, infos, info);
        }

        const builtin_classes = try arena.alloc(ExtensionApiJson.BuiltinClass, api.builtin_classes.len);
        for (api.builtin_classes, 0..) |builtin, builtin_index| {
            var builtin_copy = builtin;
            const methods = try arena.alloc(ExtensionApiJson.Method, builtin.methods.len);
            for (builtin.methods, 0..) |method_value, method_index| {
                var method = method_value;
                const description = method.description orelse {
                    methods[method_index] = method;
                    continue;
                };
                if (method.arguments.len != 0) {
                    const arguments = try arena.alloc(ExtensionApiJson.Argument, method.arguments.len);
                    for (method.arguments, 0..) |argument_value, argument_index| {
                        var argument = argument_value;
                        if (try inferBuiltinEnumArgument(arena, api, &builtin_copy, &argument, description)) |inferred| {
                            argument.type = inferred;
                        }
                        arguments[argument_index] = argument;
                    }
                    method.arguments = arguments;
                }
                methods[method_index] = method;
            }
            builtin_copy.methods = methods;
            builtin_classes[builtin_index] = builtin_copy;
        }

        return .{
            .api = api,
            .arena = arena,
            .infos = infos,
            .builtin_classes = builtin_classes,
            .real_type = real_type,
            .renames = try buildRenames(arena, api),
            .builtin_names = builtin_names,
        };
    }

    pub fn builtinClass(self: ClassResolver, name: []const u8) ?*const ExtensionApiJson.BuiltinClass {
        for (self.builtin_classes) |*builtin| {
            if (std.mem.eql(u8, builtin.name, name)) return builtin;
        }
        return null;
    }

    pub fn isBuiltin(self: ClassResolver, name: []const u8) bool {
        for (self.builtin_names) |builtin_name| {
            if (std.mem.eql(u8, builtin_name, name)) return true;
        }
        return false;
    }

    pub fn zigClassName(self: ClassResolver, name: []const u8) []const u8 {
        for (self.renames) |rename| {
            if (std.mem.eql(u8, rename.name, name)) return rename.alias;
        }
        return name;
    }

    pub fn get(self: ClassResolver, name: []const u8) ?*const Info {
        return if (indexOf(self.infos, name)) |index| &self.infos[index] else null;
    }

    pub fn baseInfo(self: ClassResolver, info: *const Info) ?*const Info {
        const base_index = info.base orelse return null;
        return &self.infos[base_index];
    }

    pub fn isNative(self: ClassResolver, name: []const u8) bool {
        for (self.api.native_structures) |structure| {
            if (std.mem.eql(u8, structure.name, name)) return true;
        }
        return false;
    }

    pub fn virtualName(self: ClassResolver, info: *const Info, raw: []const u8) []const u8 {
        _ = self;
        for (info.virtual_names) |entry| {
            if (std.mem.eql(u8, entry.raw, raw)) return entry.zig;
        }
        return raw;
    }

    pub fn path(self: ClassResolver, arena: Allocator, info: *const Info) ![]const u8 {
        _ = self;
        return classPath(arena, info.class, "classes");
    }

    pub fn relativeClassImport(self: ClassResolver, arena: Allocator, from: *const Info, to: *const Info) ![]const u8 {
        _ = self;
        const from_api = from.class.api_type;
        const to_api = to.class.api_type;
        const to_file = try names.snake(arena, to.class.name);

        if (from_api == null and to_api == null) {
            return std.fmt.allocPrint(arena, "{s}.zig", .{to_file});
        }
        if (from_api != null and to_api != null and std.mem.eql(u8, from_api.?, to_api.?)) {
            return std.fmt.allocPrint(arena, "{s}.zig", .{to_file});
        }
        if (from_api != null and to_api == null) {
            return std.fmt.allocPrint(arena, "../{s}.zig", .{to_file});
        }
        if (from_api == null and to_api != null) {
            return std.fmt.allocPrint(arena, "{s}/{s}.zig", .{ to_api.?, to_file });
        }
        return std.fmt.allocPrint(arena, "../{s}/{s}.zig", .{ to_api.?, to_file });
    }

    pub fn rootPrefix(self: ClassResolver, arena: Allocator, info: *const Info) ![]const u8 {
        _ = self;
        _ = arena;
        return if (info.class.api_type == null) "../" else "../../";
    }

    pub fn resolve(self: ClassResolver, raw: []const u8, context: TypeContext) !ResolvedType {
        return self.resolveFor(raw, context, .class_file);
    }

    pub fn resolveFor(self: ClassResolver, raw: []const u8, context: TypeContext, scope: Scope) !ResolvedType {
        var name = std.mem.trim(u8, raw, " ");
        if (std.mem.startsWith(u8, name, "const ")) name = std.mem.trim(u8, name["const ".len..], " ");

        var pointer_depth: usize = 0;
        while (std.mem.endsWith(u8, name, "*")) {
            pointer_depth += 1;
            name = std.mem.trimEnd(u8, name[0 .. name.len - 1], " ");
        }

        if (pointer_depth != 0) {
            if (self.get(name)) |info| {
                return self.classPointer(scope, info, context);
            }
            if (self.isNative(name)) {
                const zig = if (context == .return_value)
                    try std.fmt.allocPrint(self.arena, "?*native.{s}", .{name})
                else
                    try std.fmt.allocPrint(self.arena, "*native.{s}", .{name});
                return .{ .kind = .native_ptr, .zig = zig, .import_native = true };
            }
            if (pointer_depth == 1) {
                if (primitivePointerType(name)) |base| {
                    const zig = if (context == .return_value)
                        try std.fmt.allocPrint(self.arena, "?*{s}", .{base})
                    else
                        try std.fmt.allocPrint(self.arena, "*{s}", .{base});
                    return .{ .kind = .primitive, .zig = zig };
                }
            }
            return .{ .kind = .primitive, .zig = "?*anyopaque" };
        }

        if (std.mem.eql(u8, name, "void") or std.mem.eql(u8, name, "Nil")) {
            return .{ .kind = .void, .zig = "void" };
        }
        if (std.mem.eql(u8, name, "float")) {
            return .{ .kind = .primitive, .zig = self.real_type };
        }
        if (std.mem.eql(u8, name, "int")) {
            return .{ .kind = .primitive, .zig = "i64" };
        }
        if (std.mem.eql(u8, name, "bool")) {
            return .{ .kind = .primitive, .zig = "bool" };
        }
        if (std.mem.eql(u8, name, "Variant")) {
            return .{ .kind = .variant, .zig = try self.builtinRef(scope, "Variant") };
        }
        if (std.mem.startsWith(u8, name, "typedarray::")) {
            return .{ .kind = .builtin, .zig = try self.builtinRef(scope, "Array") };
        }
        if (std.mem.startsWith(u8, name, "typeddictionary::")) {
            return .{ .kind = .builtin, .zig = try self.builtinRef(scope, "Dictionary") };
        }
        if (std.mem.startsWith(u8, name, "enum::") or std.mem.startsWith(u8, name, "bitfield::")) {
            return self.resolveEnum(name, context, scope);
        }
        if (self.get(name)) |info| {
            return self.classPointer(scope, info, context);
        }
        if (self.isBuiltin(name)) {
            return .{ .kind = .builtin, .zig = try self.builtinRef(scope, name) };
        }
        std.log.err("Unresolved type: {s}", .{raw});
        return error.UnresolvedType;
    }

    fn builtinRef(self: ClassResolver, scope: Scope, name: []const u8) ![]const u8 {
        if (scope == .builtin_file) return name;
        return std.fmt.allocPrint(self.arena, "builtins.{s}", .{name});
    }

    fn zigClassPath(self: ClassResolver, info: *const Info) ![]const u8 {
        if (info.class.api_type) |api_type| {
            return std.fmt.allocPrint(self.arena, "classes.{s}.{s}", .{ api_type, info.class.name });
        }
        return std.fmt.allocPrint(self.arena, "classes.{s}", .{info.class.name});
    }

    fn classPointer(self: ClassResolver, scope: Scope, info: *const Info, context: TypeContext) !ResolvedType {
        if (scope == .class_file) {
            const zig = if (context == .return_value)
                try std.fmt.allocPrint(self.arena, "?*{s}", .{self.zigClassName(info.class.name)})
            else
                try std.fmt.allocPrint(self.arena, "*{s}", .{self.zigClassName(info.class.name)});
            return .{ .kind = .class_ptr, .zig = zig, .import_class = info.class.name };
        }

        const class_path = try self.zigClassPath(info);
        const zig = if (context == .return_value)
            try std.fmt.allocPrint(self.arena, "?*{s}", .{class_path})
        else
            try std.fmt.allocPrint(self.arena, "*{s}", .{class_path});
        return .{ .kind = .class_ptr, .zig = zig, .use_classes = true };
    }

    fn classEnum(self: ClassResolver, scope: Scope, info: *const Info, enum_name: []const u8, class_enum: ExtensionApiJson.GlobalEnum) !ResolvedType {
        const zig_enum_name = try names.pascal(self.arena, enum_name);
        const bits = bitfieldBits(class_enum.values);
        if (scope == .class_file) {
            return .{
                .kind = .@"enum",
                .zig = try std.fmt.allocPrint(self.arena, "{s}.{s}", .{ self.zigClassName(info.class.name), zig_enum_name }),
                .import_class = info.class.name,
                .is_bitfield = class_enum.is_bitfield,
                .bitfield_bits = bits,
            };
        }

        const class_path = try self.zigClassPath(info);
        return .{
            .kind = .@"enum",
            .zig = try std.fmt.allocPrint(self.arena, "{s}.{s}", .{ class_path, zig_enum_name }),
            .use_classes = true,
            .is_bitfield = class_enum.is_bitfield,
            .bitfield_bits = bits,
        };
    }

    fn resolveEnum(self: ClassResolver, raw: []const u8, context: TypeContext, scope: Scope) !ResolvedType {
        _ = context;
        const rest = if (std.mem.startsWith(u8, raw, "enum::")) raw["enum::".len..] else raw["bitfield::".len..];

        if (std.mem.indexOfScalar(u8, rest, '.')) |dot| {
            const class_name = rest[0..dot];
            const enum_name = rest[dot + 1 ..];
            if (self.get(class_name)) |info| {
                for (info.class.enums) |class_enum| {
                    if (std.mem.eql(u8, class_enum.name, enum_name)) {
                        return self.classEnum(scope, info, enum_name, class_enum);
                    }
                }
            }
            for (self.api.builtin_classes) |builtin| {
                if (!std.mem.eql(u8, builtin.name, class_name)) continue;
                for (builtin.enums) |builtin_enum| {
                    if (std.mem.eql(u8, builtin_enum.name, enum_name)) {
                        const zig_enum_name = try names.pascal(self.arena, enum_name);
                        const zig = if (scope == .builtin_file)
                            try std.fmt.allocPrint(self.arena, "{s}.{s}", .{ class_name, zig_enum_name })
                        else
                            try std.fmt.allocPrint(self.arena, "builtins.{s}.{s}", .{ class_name, zig_enum_name });
                        return .{
                            .kind = .@"enum",
                            .zig = zig,
                            .is_bitfield = builtin_enum.is_bitfield,
                            .bitfield_bits = bitfieldBits(builtin_enum.values),
                        };
                    }
                }
            }
        }

        for (self.api.global_enums) |global_enum| {
            if (std.mem.eql(u8, global_enum.name, rest)) {
                const zig_name = try names.pascal(self.arena, global_enum.name);
                return .{
                    .kind = .@"enum",
                    .zig = try std.fmt.allocPrint(self.arena, "enums.{s}", .{zig_name}),
                    .import_enums = true,
                    .is_bitfield = global_enum.is_bitfield,
                    .bitfield_bits = bitfieldBits(global_enum.values),
                };
            }
        }
        std.log.err("Unresolved enum type: {s}", .{raw});
        return error.UnresolvedEnum;
    }
};

pub fn classPath(arena: Allocator, class: *const ExtensionApiJson.Class, root: []const u8) ![]const u8 {
    const file_name = try names.snake(arena, class.name);
    if (class.api_type) |api_type| {
        return std.fmt.allocPrint(arena, "{s}/{s}/{s}.zig", .{ root, api_type, file_name });
    }
    return std.fmt.allocPrint(arena, "{s}/{s}.zig", .{ root, file_name });
}

fn indexOf(infos: []const Info, name: []const u8) ?usize {
    var low: usize = 0;
    var high: usize = infos.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        switch (std.mem.order(u8, infos[mid].class.name, name)) {
            .lt => low = mid + 1,
            .gt => high = mid,
            .eq => return mid,
        }
    }
    return null;
}

fn lessThanInfo(_: void, a: Info, b: Info) bool {
    return std.mem.order(u8, a.class.name, b.class.name) == .lt;
}

fn inferEnumArgument(
    arena: Allocator,
    api: ExtensionApiJson,
    class: *const ExtensionApiJson.Class,
    argument: *const ExtensionApiJson.Argument,
    description: []const u8,
) !?[]const u8 {
    const enum_ref = try inferEnumReference(arena, argument, description) orelse return null;
    return resolveDocEnum(arena, api, class, enum_ref);
}

fn inferBuiltinEnumArgument(
    arena: Allocator,
    api: ExtensionApiJson,
    builtin: *const ExtensionApiJson.BuiltinClass,
    argument: *const ExtensionApiJson.Argument,
    description: []const u8,
) !?[]const u8 {
    const enum_ref = try inferEnumReference(arena, argument, description) orelse return null;
    return resolveDocEnumBuiltin(arena, api, builtin, enum_ref);
}

fn inferEnumReference(
    arena: Allocator,
    argument: *const ExtensionApiJson.Argument,
    description: []const u8,
) !?[]const u8 {
    if (!std.mem.eql(u8, argument.type, "int") or argument.name.len == 0) return null;
    const clean_name = stripParamPrefix(argument.name);
    const marker = try std.fmt.allocPrint(arena, "[param {s}]", .{argument.name});
    const clean_marker = if (std.mem.eql(u8, clean_name, argument.name))
        marker
    else
        try std.fmt.allocPrint(arena, "[param {s}]", .{clean_name});

    var sentences = std.mem.splitScalar(u8, description, '.');
    while (sentences.next()) |sentence| {
        const raw_index = std.mem.indexOf(u8, sentence, marker);
        const clean_index = if (std.mem.eql(u8, marker, clean_marker))
            raw_index
        else
            std.mem.indexOf(u8, sentence, clean_marker);

        const param_index = if (raw_index == null)
            clean_index orelse continue
        else if (clean_index == null or raw_index.? <= clean_index.?)
            raw_index.?
        else
            clean_index.?;
        const marker_len = if (raw_index != null and param_index == raw_index.?)
            marker.len
        else
            clean_marker.len;

        const after_param = sentence[param_index + marker_len ..];
        const enum_index = std.mem.indexOf(u8, after_param, "[enum ") orelse continue;
        if (std.mem.indexOf(u8, after_param[0..enum_index], "[param ") != null) continue;
        const enum_ref = findEnumTag(after_param[enum_index..]) orelse continue;
        if (!enumMatchesArgument(enum_ref, clean_name)) continue;
        return enum_ref;
    }
    return null;
}

fn stripParamPrefix(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, "p_")) name["p_".len..] else name;
}

fn enumMatchesArgument(enum_ref: []const u8, argument_name: []const u8) bool {
    var reference = enum_ref;
    if (std.mem.startsWith(u8, reference, "@GlobalScope.")) reference = reference["@GlobalScope.".len..];
    const short_name = if (std.mem.lastIndexOfScalar(u8, reference, '.')) |dot| reference[dot + 1 ..] else reference;
    const clean_argument = stripParamPrefix(argument_name);

    var arg_buf: [128]u8 = undefined;
    var enum_buf: [128]u8 = undefined;
    const arg_len = normalizedLower(clean_argument, &arg_buf);
    const enum_len = normalizedLower(short_name, &enum_buf);
    if (arg_len < 3 or enum_len < 3) return false;
    return containsIgnoreCase(enum_buf[0..enum_len], arg_buf[0..arg_len]) or
        containsIgnoreCase(arg_buf[0..arg_len], enum_buf[0..enum_len]);
}

fn normalizedLower(input: []const u8, buffer: *[128]u8) usize {
    var length: usize = 0;
    for (input) |c| {
        if (c == '_') continue;
        if (length == buffer.len) break;
        buffer[length] = std.ascii.toLower(c);
        length += 1;
    }
    return length;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.mem.eql(u8, haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn findEnumTag(text: []const u8) ?[]const u8 {
    const start_marker = "[enum ";
    var offset: usize = 0;
    while (std.mem.indexOf(u8, text[offset..], start_marker)) |relative| {
        const start = offset + relative + start_marker.len;
        const end = std.mem.indexOfScalar(u8, text[start..], ']') orelse return null;
        if (end != 0) return text[start .. start + end];
        offset = start + end + 1;
    }
    return null;
}

fn resolveDocEnum(
    arena: Allocator,
    api: ExtensionApiJson,
    current: *const ExtensionApiJson.Class,
    reference: []const u8,
) !?[]const u8 {
    if (std.mem.startsWith(u8, reference, "@GlobalScope.")) {
        const name = reference["@GlobalScope.".len..];
        if (hasGlobalEnum(api, name)) return try std.fmt.allocPrint(arena, "enum::{s}", .{name});
        return null;
    }

    if (std.mem.indexOfScalar(u8, reference, '.')) |dot| {
        const class_name = reference[0..dot];
        const enum_name = reference[dot + 1 ..];
        if (findClass(api, class_name)) |owner| {
            if (classHasEnum(owner, enum_name)) {
                return try std.fmt.allocPrint(arena, "enum::{s}.{s}", .{ class_name, enum_name });
            }
        }
        if (hasGlobalEnum(api, reference)) {
            return try std.fmt.allocPrint(arena, "enum::{s}", .{reference});
        }
        return null;
    }

    var owner = current;
    while (true) {
        if (classHasEnum(owner, reference)) {
            return try std.fmt.allocPrint(arena, "enum::{s}.{s}", .{ owner.name, reference });
        }
        owner = findBase(api, owner) orelse break;
    }
    if (hasGlobalEnum(api, reference)) return try std.fmt.allocPrint(arena, "enum::{s}", .{reference});
    return null;
}

fn resolveDocEnumBuiltin(
    arena: Allocator,
    api: ExtensionApiJson,
    current: *const ExtensionApiJson.BuiltinClass,
    reference: []const u8,
) !?[]const u8 {
    if (std.mem.startsWith(u8, reference, "@GlobalScope.")) {
        const name = reference["@GlobalScope.".len..];
        if (hasGlobalEnum(api, name)) return try std.fmt.allocPrint(arena, "enum::{s}", .{name});
        return null;
    }

    if (std.mem.indexOfScalar(u8, reference, '.')) |dot| {
        const owner_name = reference[0..dot];
        const enum_name = reference[dot + 1 ..];
        if (findBuiltin(api, owner_name)) |owner| {
            if (builtinHasEnum(owner, enum_name)) {
                return try std.fmt.allocPrint(arena, "enum::{s}.{s}", .{ owner_name, enum_name });
            }
        }
        if (findClass(api, owner_name)) |owner| {
            if (classHasEnum(owner, enum_name)) {
                return try std.fmt.allocPrint(arena, "enum::{s}.{s}", .{ owner_name, enum_name });
            }
        }
        if (hasGlobalEnum(api, reference)) {
            return try std.fmt.allocPrint(arena, "enum::{s}", .{reference});
        }
        return null;
    }

    if (builtinHasEnum(current, reference)) {
        return try std.fmt.allocPrint(arena, "enum::{s}.{s}", .{ current.name, reference });
    }
    if (hasGlobalEnum(api, reference)) return try std.fmt.allocPrint(arena, "enum::{s}", .{reference});
    return null;
}

fn findBuiltin(api: ExtensionApiJson, name: []const u8) ?*const ExtensionApiJson.BuiltinClass {
    for (api.builtin_classes) |*builtin| {
        if (std.mem.eql(u8, builtin.name, name)) return builtin;
    }
    return null;
}

fn builtinHasEnum(builtin: *const ExtensionApiJson.BuiltinClass, name: []const u8) bool {
    for (builtin.enums) |builtin_enum| {
        if (std.mem.eql(u8, builtin_enum.name, name)) return true;
    }
    return false;
}

fn findClass(api: ExtensionApiJson, name: []const u8) ?*const ExtensionApiJson.Class {
    for (api.classes) |*class| {
        if (std.mem.eql(u8, class.name, name)) return class;
    }
    return null;
}

fn findBase(api: ExtensionApiJson, class: *const ExtensionApiJson.Class) ?*const ExtensionApiJson.Class {
    const base_name = class.inherits orelse return null;
    return findClass(api, base_name);
}

fn classHasEnum(class: *const ExtensionApiJson.Class, name: []const u8) bool {
    for (class.enums) |class_enum| {
        if (std.mem.eql(u8, class_enum.name, name)) return true;
    }
    return false;
}

fn hasGlobalEnum(api: ExtensionApiJson, name: []const u8) bool {
    for (api.global_enums) |global_enum| {
        if (std.mem.eql(u8, global_enum.name, name)) return true;
    }
    return false;
}

fn buildVirtualNames(arena: Allocator, infos: []const Info, info: *const Info) ![]const VirtualName {
    var used: [2048][]const u8 = undefined;
    var used_count: usize = 0;
    var entries: [2048]VirtualName = undefined;
    var entry_count: usize = 0;

    for (info.class.methods) |method| {
        if (method.is_virtual) continue;
        const camel = try names.camel(arena, method.name);
        used[used_count] = camel;
        used_count += 1;
    }

    var current: ?*const Info = info;
    while (current) |class_info| {
        for (class_info.class.methods) |method| {
            if (!method.is_virtual) continue;
            var already = false;
            for (entries[0..entry_count]) |entry| {
                if (std.mem.eql(u8, entry.raw, method.name)) {
                    already = true;
                    break;
                }
            }
            if (already) continue;

            const camel = try names.camel(arena, method.name);
            var candidate = try std.fmt.allocPrint(arena, "_{s}", .{camel});
            while (isUsed(used[0..used_count], candidate)) {
                candidate = try std.fmt.allocPrint(arena, "{s}V", .{candidate});
            }

            used[used_count] = candidate;
            used_count += 1;
            entries[entry_count] = .{ .raw = method.name, .zig = candidate };
            entry_count += 1;
        }
        current = if (class_info.base) |base_index| &infos[base_index] else null;
    }

    return arena.dupe(VirtualName, entries[0..entry_count]);
}

fn isUsed(used: []const []const u8, name: []const u8) bool {
    for (used) |existing| {
        if (std.mem.eql(u8, existing, name)) return true;
    }
    return false;
}

fn buildRenames(arena: Allocator, api: ExtensionApiJson) ![]const Rename {
    var signal_total: usize = 0;
    for (api.classes) |class| signal_total += class.signals.len;
    const signal_names = try arena.alloc([]const u8, signal_total);
    var signal_count: usize = 0;
    for (api.classes) |class| {
        for (class.signals) |signal| {
            signal_names[signal_count] = try names.pascal(arena, signal.name);
            signal_count += 1;
        }
    }

    const renames = try arena.alloc(Rename, api.classes.len);
    var rename_count: usize = 0;
    for (api.classes) |class| {
        for (signal_names[0..signal_count]) |signal_name| {
            if (!std.mem.eql(u8, class.name, signal_name)) continue;
            renames[rename_count] = .{
                .name = class.name,
                .alias = try std.fmt.allocPrint(arena, "{s}Class", .{class.name}),
            };
            rename_count += 1;
            break;
        }
    }
    return renames[0..rename_count];
}

fn bitfieldBits(values: []const ExtensionApiJson.GlobalEnumValue) u8 {
    var max_value: u64 = 0;
    for (values) |value| {
        if (value.value > 0) {
            max_value = @max(max_value, @as(u64, @intCast(value.value)));
        }
    }
    return if (max_value > std.math.maxInt(u32)) 64 else 32;
}

fn primitivePointerType(name: []const u8) ?[]const u8 {
    const primitives = [_]struct { name: []const u8, zig: []const u8 }{
        .{ .name = "bool", .zig = "bool" },
        .{ .name = "char", .zig = "u8" },
        .{ .name = "double", .zig = "f64" },
        .{ .name = "float", .zig = "f32" },
        .{ .name = "int", .zig = "i64" },
        .{ .name = "int8_t", .zig = "i8" },
        .{ .name = "int16_t", .zig = "i16" },
        .{ .name = "int32_t", .zig = "i32" },
        .{ .name = "int64_t", .zig = "i64" },
        .{ .name = "uint8_t", .zig = "u8" },
        .{ .name = "uint16_t", .zig = "u16" },
        .{ .name = "uint32_t", .zig = "u32" },
        .{ .name = "uint64_t", .zig = "u64" },
        .{ .name = "uintptr_t", .zig = "usize" },
        .{ .name = "void", .zig = "anyopaque" },
    };
    for (primitives) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry.zig;
    }
    return null;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const names = @import("names.zig");
const ExtensionApiJson = @import("ExtensionApiJson.zig");
