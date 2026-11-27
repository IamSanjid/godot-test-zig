//! `Method`/`Methods` declaration markers and method discovery. See
//! docs/classdb.md.

/// Wraps a tuple of `Method` markers as a class-level declaration marker.
///
/// The container declaration name is free; discovery appends every container's
/// entries in declaration order.
pub fn Methods(comptime p_methods: anytype) type {
    if (!reflect.isTuple(@TypeOf(p_methods))) @compileError(
        "Methods expects a tuple of Method markers, e.g. `Methods(.{ Method(.ping, .{}) })`; found: " ++
            @typeName(@TypeOf(p_methods)),
    );
    inline for (p_methods, 0..) |entry, index| {
        if (comptime @TypeOf(entry) != type) @compileError(std.fmt.comptimePrint(
            "Methods entry {d} must be a Method marker; wrap the implementation with godot.annotations.Method(...).",
            .{index},
        ));
        if (comptime !isMethod(entry)) @compileError(std.fmt.comptimePrint(
            "Methods entry {d} is not a Method marker; wrap the implementation with godot.annotations.Method(...).",
            .{index},
        ));
    }

    return struct {
        /// Method markers in declaration order.
        pub const methods = p_methods;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.methods;
    };
}

/// Declares one engine method.
///
/// `the_method` is an enum literal naming a function on the class or a direct
/// function reference. A direct reference requires `.name`; an enum literal
/// defaults to its tag converted with `naming.comptimeConvert(.godot, .method,
/// ...)`. Other options: `.arg_names`, a tuple of engine argument names in
/// engine order (`"arg0"`, `"arg1"`, ... when omitted), and `.is_static`
/// (default false).
pub fn Method(comptime the_method: anytype, comptime p_options: anytype) type {
    const OptionsT = @TypeOf(p_options);
    validateOptions(p_options);

    const explicit_name: ?[:0]const u8 = if (@hasField(OptionsT, "name")) p_options.name else null;
    if (explicit_name) |engine_name| {
        if (engine_name.len == 0) @compileError("Method .name must not be empty");
    }

    const TargetT = @TypeOf(the_method);
    const engine_name: [:0]const u8 = if (comptime TargetT == @EnumLiteral())
        explicit_name orelse naming.comptimeConvert(.godot, .method, @tagName(the_method))
    else if (comptime @typeInfo(TargetT) == .@"fn")
        explicit_name orelse @compileError(
            "Method takes a direct function reference, so it requires the '.name' option, " ++
                "e.g. `Method(helper, .{ .name = \"helper\" })`.",
        )
    else
        @compileError(
            "Method expects an enum literal naming a class function or a direct function reference; found: " ++
                @typeName(TargetT),
        );

    return struct {
        /// Implementation selector: an enum literal naming a class function or a
        /// direct function value.
        pub const target = the_method;
        /// Raw options: the `.name`, `.arg_names`, and `.is_static` fields present
        /// in the marker.
        pub const options = p_options;
        /// Engine-facing method name.
        pub const name = engine_name;
        /// Annotation marker identity; see annotations/marker.zig.
        pub const marker = marker_kind.Kind.method;
    };
}

/// Resolved methods declared by `T`, flattened across its `Methods` markers in
/// declaration order.
///
/// Each element is a distinct entry type because entries are heterogeneous:
/// their implementation signatures differ. Entry declarations are documented on
/// `MethodEntry`.
pub fn findMethods(comptime T: type) []const type {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("Expected a class struct, found: " ++ @typeName(T));

        const decl_names = @typeInfo(T).@"struct".decl_names;
        var total: usize = 0;
        for (decl_names) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isMethods(Decl)) continue;
            total += Decl.methods.len;
        }

        var entries: [total]type = undefined;
        var count: usize = 0;
        for (decl_names) |decl_name| {
            const Decl = @field(T, decl_name);
            if (@TypeOf(Decl) != type or !isMethods(Decl)) continue;
            for (Decl.methods) |marker| {
                entries[count] = resolveMethod(T, marker);
                count += 1;
            }
        }

        checkDuplicateNames(T, entries[0..count]);
        const out = entries[0..count].*;
        return &out;
    }
}

/// True when `OtherT` is a type produced by `Method`.
fn isMethod(comptime OtherT: type) bool {
    if (!marker_kind.is(OtherT, .method)) return false;
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "target") or !@hasDecl(OtherT, "options")) return false;
    return OtherT == Method(OtherT.target, OtherT.options);
}

/// True when `OtherT` is a type produced by `Methods`.
fn isMethods(comptime OtherT: type) bool {
    if (!marker_kind.is(OtherT, .methods)) return false;
    if (@typeInfo(OtherT) != .@"struct") return false;
    if (!@hasDecl(OtherT, "methods")) return false;
    return OtherT == Methods(OtherT.methods);
}

fn validateOptions(comptime p_options: anytype) void {
    const OptionsT = @TypeOf(p_options);
    const info = @typeInfo(OptionsT);
    // `.{}` is the empty tuple; any other option shape must be a struct literal.
    const accepted = switch (info) {
        .@"struct" => |struct_info| struct_info.field_names.len == 0 or !struct_info.is_tuple,
        else => false,
    };
    if (!accepted) @compileError(
        "Method options must be an anonymous struct literal, e.g. .{ .arg_names = .{\"value\"} }; found: " ++
            @typeName(OptionsT),
    );
    inline for (info.@"struct".field_names) |key| {
        if (comptime !option_keys.has(key)) @compileError(std.fmt.comptimePrint(
            "Method has unknown option '.{s}'; supported options are .name, .arg_names, and .is_static.",
            .{key},
        ));
    }
    if (@hasField(OptionsT, "is_static")) {
        if (@TypeOf(p_options.is_static) != bool) @compileError(
            "Method .is_static must be a bool, found: " ++ @typeName(@TypeOf(p_options.is_static)),
        );
    }
    if (@hasField(OptionsT, "arg_names")) validateArgNames(p_options.arg_names);
}

fn validateArgNames(comptime arg_names: anytype) void {
    const ArgNamesT = @TypeOf(arg_names);
    if (!reflect.isTuple(ArgNamesT)) @compileError(
        "Method .arg_names must be a tuple of string literals in engine order, e.g. .{\"target\"}; found: " ++
            @typeName(ArgNamesT),
    );
    inline for (arg_names, 0..) |arg_name, index| {
        const name: [:0]const u8 = arg_name;
        if (name.len == 0) @compileError(std.fmt.comptimePrint(
            "Method .arg_names[{d}] must not be empty",
            .{index},
        ));
    }
}

/// Resolves one marker against class `T` into its entry type.
fn resolveMethod(comptime T: type, comptime marker: type) type {
    if (comptime @TypeOf(marker.target) == @EnumLiteral()) {
        const tag = @tagName(marker.target);
        if (comptime !@hasDecl(T, tag)) @compileError(std.fmt.comptimePrint(
            "Method '{s}' names '.{s}', but '{s}' has no visible function of that name. " ++
                "An enum-literal implementation must be a 'pub fn' declaration; a private function " ++
                "can be passed directly instead.",
            .{ marker.name, tag, @typeName(T) },
        ));
        const Implementation = @field(T, tag);
        if (@TypeOf(Implementation) == type) @compileError(std.fmt.comptimePrint(
            "Method '{s}' names '.{s}', but '{s}.{s}' is a type, not a function.",
            .{ marker.name, tag, @typeName(T), tag },
        ));
        if (@typeInfo(@TypeOf(Implementation)) != .@"fn") @compileError(std.fmt.comptimePrint(
            "Method '{s}' names '.{s}', but '{s}.{s}' is not a function.",
            .{ marker.name, tag, @typeName(T), tag },
        ));
        return MethodEntry(T, marker, Implementation);
    }
    return MethodEntry(T, marker, marker.target);
}

/// Entry type for one resolved method. Declarations:
/// - `name`: engine-facing name, verbatim.
/// - `implementation`: the class function or direct function reference.
/// - `Fn`: implementation function type; the self parameter is first when the
///   method is not static.
/// - `is_static`/`is_const`: the engine flags derived from the marker and the
///   self parameter.
/// - `arg_count`: number of engine arguments, excluding self.
/// - `arg_names`: explicit `.arg_names` in engine order; empty when omitted.
/// - `argName(index)`: registered argument name, explicit or `arg<index>`.
fn MethodEntry(comptime T: type, comptime marker: type, comptime function: anytype) type {
    const Function = @TypeOf(function);
    const fn_info = @typeInfo(Function).@"fn";
    const OptionsT = @TypeOf(marker.options);
    const static_method: bool = if (@hasField(OptionsT, "is_static")) marker.options.is_static else false;
    const signature = validateSignature(T, marker.name, static_method, fn_info);

    const has_arg_names = @hasField(OptionsT, "arg_names");
    const explicit_names: []const [:0]const u8 = if (has_arg_names)
        argNames(marker.options.arg_names)
    else
        &.{};
    if (has_arg_names and explicit_names.len != signature.arg_count) @compileError(std.fmt.comptimePrint(
        "Method '{s}' declares {d} '.arg_names' entry but has {d} engine argument(s).",
        .{ marker.name, explicit_names.len, signature.arg_count },
    ));

    const spec = .{
        .name = marker.name,
        .implementation = function,
        .Fn = Function,
        .is_static = static_method,
        .is_const = signature.is_const,
        .arg_count = signature.arg_count,
        .arg_names = explicit_names,
    };

    return struct {
        pub const name = spec.name;
        pub const implementation = spec.implementation;
        pub const Fn = spec.Fn;
        pub const is_static = spec.is_static;
        /// True when the self parameter is `*const T`; false for a static method.
        pub const is_const = spec.is_const;
        pub const arg_count = spec.arg_count;
        pub const arg_names = spec.arg_names;

        /// Engine-facing name for engine argument `index`: the explicit
        /// `.arg_names` entry, or the `arg<index>` fallback.
        pub fn argName(comptime index: usize) [:0]const u8 {
            return comptime blk: {
                if (index >= arg_count) @compileError(std.fmt.comptimePrint(
                    "Method '{s}' has no engine argument {d}.",
                    .{ name, index },
                ));
                if (index < arg_names.len) break :blk arg_names[index];
                break :blk std.fmt.comptimePrint("arg{d}", .{index});
            };
        }
    };
}

/// Facts derived from an implementation signature.
const Signature = struct {
    is_const: bool,
    arg_count: usize,
};

fn validateSignature(
    comptime T: type,
    comptime name: [:0]const u8,
    comptime is_static: bool,
    comptime fn_info: std.lang.Type.Fn,
) Signature {
    if (fn_info.is_generic) @compileError(std.fmt.comptimePrint(
        "Method '{s}' must be a non-generic function.",
        .{name},
    ));
    if (fn_info.attrs.varargs) @compileError(std.fmt.comptimePrint(
        "Method '{s}' must not be variadic.",
        .{name},
    ));

    var engine_offset: usize = 0;
    var is_const = false;
    if (!is_static) {
        const self_param = if (fn_info.param_types.len == 0)
            @compileError(std.fmt.comptimePrint(
                "Method '{s}' must take a self parameter of type '*{s}' or '*const {s}' as its first " ++
                    "argument; mark it '.is_static = true' when it has no self parameter.",
                .{ name, @typeName(T), @typeName(T) },
            ))
        else
            fn_info.param_types[0] orelse @compileError(std.fmt.comptimePrint(
                "Method '{s}' self parameter has no concrete type; a generic method is not supported.",
                .{name},
            ));
        is_const = selfPtrConstness(T, self_param) orelse @compileError(std.fmt.comptimePrint(
            "Method '{s}' first parameter must be '*{s}' or '*const {s}'; found: {s}.",
            .{ name, @typeName(T), @typeName(T), @typeName(self_param) },
        ));
        engine_offset = 1;
    } else if (fn_info.param_types.len != 0) {
        const first = fn_info.param_types[0] orelse @compileError(std.fmt.comptimePrint(
            "Method '{s}' argument 0 has no concrete type; a generic method is not supported.",
            .{name},
        ));
        if (selfPtrConstness(T, first) != null) @compileError(std.fmt.comptimePrint(
            "Method '{s}' is marked '.is_static = true' but takes a self parameter; remove the parameter " ++
                "or the flag.",
            .{name},
        ));
    }

    inline for (fn_info.param_types[engine_offset..], 0..) |maybe_param, index| {
        const Param = maybe_param orelse @compileError(std.fmt.comptimePrint(
            "Method '{s}' argument {d} has no concrete type; a generic method is not supported.",
            .{ name, index },
        ));
        const context = comptime std.fmt.comptimePrint("Method '{s}' argument {d}", .{ name, index });
        conversion.checkBoth(Param, context);
        conversion.checkMethodArgument(Param, context);
    }
    const Return = fn_info.return_type orelse void;
    if (comptime Return != void) {
        conversion.checkBoth(Return, std.fmt.comptimePrint("Method '{s}' return value", .{name}));
    }

    return .{
        .is_const = is_const,
        .arg_count = fn_info.param_types.len - engine_offset,
    };
}

/// The explicit `.arg_names` tuple as a comptime slice.
fn argNames(comptime p_arg_names: anytype) []const [:0]const u8 {
    var names: [p_arg_names.len][:0]const u8 = undefined;
    inline for (p_arg_names, 0..) |arg_name, index| names[index] = arg_name;
    const out = names;
    return &out;
}

/// True for `*T` (false) and `*const T` (true); null for any other type.
fn selfPtrConstness(comptime T: type, comptime Param: type) ?bool {
    const info = @typeInfo(Param);
    if (info != .pointer or info.pointer.size != .one) return null;
    if (info.pointer.child != T) return null;
    return info.pointer.attrs.@"const";
}

fn checkDuplicateNames(comptime T: type, comptime entries: []const type) void {
    for (entries, 0..) |Entry, i| {
        for (entries[i + 1 ..]) |Other| {
            if (std.mem.eql(u8, Entry.name, Other.name)) @compileError(std.fmt.comptimePrint(
                "Class '{s}' declares method '{s}' twice. Rename one Method marker.",
                .{ @typeName(T), Entry.name },
            ));
        }
    }
}

const std = @import("std");

const naming = @import("naming");

const conversion = @import("../conversion.zig");
const reflect = @import("../reflect/reflect.zig");
const marker_kind = @import("marker.zig");

const option_keys = std.StaticStringMap(void).initComptime(.{
    .{ "name", {} },
    .{ "arg_names", {} },
    .{ "is_static", {} },
});
