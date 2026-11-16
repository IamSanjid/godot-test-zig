// @templates_for Object:derived

// @section artifact inheritsFrom
fn inheritsFrom(comptime T: type, comptime Base: type) bool {
    @setEvalBranchQuota(1500); // around 1000 classes are in the Godot engine.
    comptime var Cur = T;
    inline while (true) {
        if (Cur == Base) return true;
        if (@TypeOf(Cur) != type) return false;
        const info = @typeInfo(Cur);
        if (info != .@"struct" and info != .@"opaque") return false;
        if (!@hasDecl(Cur, "Extends")) return false;
        Cur = Cur.Extends;
    }
}

// @section_end artifact inheritsFrom

// @section artifact upcast
pub inline fn upcast(self: *{{Class}}, dispatcher: anytype, comptime T: type) *T {
    _ = dispatcher;
    if (!comptime inheritsFrom({{Class}}, T)) @compileError("{{Class}} doesn't extend, " ++ @typeName(T));
    return @ptrCast(self);
}

// @section_end artifact upcast

// @section artifact downcast
pub inline fn downcast(self: *{{Class}}, dispatcher: anytype, comptime T: type) ?*T {
    const class_name = StringName.fromComptimeLatin1(dispatcher, T.GodotClassName);
    return if (self.isClass(dispatcher, class_name)) @ptrCast(self) else null;
}

// @section_end artifact downcast
