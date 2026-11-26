//! Compile-only coverage for `godot.collections`: typed owning views over the
//! engine containers and their declared conversion types.
//!
//! The analysis functions contain engine calls; they are referenced at comptime
//! and never executed.

/// Scalar converter used to analyze typed-container element conversion.
const Duration = struct {
    millis: i32,

    pub const GodotConversion = Conversion(.{
        .engine = i32,
        .to_engine = toEngine,
        .from_engine = fromEngine,
    });

    fn toEngine(self: Duration) i32 {
        return self.millis;
    }

    fn fromEngine(millis: i32) Duration {
        return .{ .millis = millis };
    }
};

/// Compile-only coverage for `Array(T)`; analyzed on every build.
fn analyzeArray(comptime T: type) void {
    const View = collections.Array(T);

    var view = View.init();
    view.append(undefined);
    view.set(0, undefined);
    _ = view.get(0);
    _ = view.len();

    var adopted = View.fromEngine(view.toEngine());
    var cloned = view.clone();
    view.deinit();
    adopted.deinit();
    cloned.deinit();
}

/// Compile-only coverage for `Dictionary(K, V)`; analyzed on every build.
fn analyzeDictionary(comptime K: type, comptime V: type) void {
    const View = collections.Dictionary(K, V);

    var view = View.init();
    _ = view.put(undefined, undefined);
    _ = view.get(undefined);
    _ = view.contains(undefined);
    _ = view.erase(undefined);
    _ = view.len();

    var adopted = View.fromEngine(view.toEngine());
    var cloned = view.clone();
    view.deinit();
    adopted.deinit();
    cloned.deinit();
}

/// Typed collection wrappers are declared conversion types: both paths go
/// through the wrapper's engine container builtin.
fn checkConversionType(comptime T: type, comptime Engine: type, comptime variant_type: interface.VariantType) void {
    const available = comptime conversion.support(T);
    if (!available.variant or !available.ptrcall) {
        @compileError("typed collection wrapper must convert on both paths: " ++ @typeName(T));
    }
    const engine = comptime conversion.engineType(T) orelse
        @compileError("typed collection wrapper must declare an engine type: " ++ @typeName(T));
    if (engine != Engine) @compileError("unexpected engine type for " ++ @typeName(T));
    if (comptime conversion.variantType(T) != variant_type) {
        @compileError("unexpected Variant type for " ++ @typeName(T));
    }
}

fn checkConversionTypes() void {
    checkConversionType(collections.Array(i32), builtins.Array, .array);
    checkConversionType(collections.Dictionary(builtins.String, i32), builtins.Dictionary, .dictionary);

    if (comptime collections.Array(i32).Element != i32) {
        @compileError("Array must expose its declared element type");
    }
    const dict = collections.Dictionary(builtins.String, i32);
    if (comptime dict.Key != builtins.String) @compileError("Dictionary must expose its declared key type");
    if (comptime dict.Value != i32) @compileError("Dictionary must expose its declared value type");
}

/// Compile-only coverage for the lazy `inline` typed-container artifacts; the
/// wrappers above only reach `setTypedAs`, so `setTyped` would otherwise stay
/// unanalyzed.
fn analyzeBuiltinTypedContainers() void {
    var array: builtins.Array = undefined;
    array.setTyped(i32, null);
    array.setTyped(?*classes.core.Node, null);
    array.setTyped(builtins.Variant, null);
    array.setTypedAs(.int, null, null);
    array.setTypedAs(.object, null, null);

    var dictionary: builtins.Dictionary = undefined;
    dictionary.setTyped(builtins.String, i32, null, null);
    dictionary.setTyped(?*classes.core.Node, builtins.Variant, null, null);
    dictionary.setTyped(builtins.Variant, builtins.Variant, null, null);
    dictionary.setTypedAs(.string, null, null, .int, null, null);
    dictionary.setTypedAs(.object, null, null, .object, null, null);
}

/// Compile-only coverage for the packed-array slice views.
fn analyzePackedSlice(comptime P: type) void {
    var value: P = undefined;
    _ = value.asSlice();
    _ = value.asSliceConst();
}

fn analyzePackedSlices() void {
    analyzePackedSlice(builtins.PackedByteArray);
    analyzePackedSlice(builtins.PackedColorArray);
    analyzePackedSlice(builtins.PackedFloat32Array);
    analyzePackedSlice(builtins.PackedFloat64Array);
    analyzePackedSlice(builtins.PackedInt32Array);
    analyzePackedSlice(builtins.PackedInt64Array);
    analyzePackedSlice(builtins.PackedStringArray);
    analyzePackedSlice(builtins.PackedVector2Array);
    analyzePackedSlice(builtins.PackedVector3Array);
    analyzePackedSlice(builtins.PackedVector4Array);
}

// Compile-only coverage; analyzed on every build.
fn analyzeCoverage() void {
    analyzeArray(i32);
    analyzeArray(builtins.String);
    analyzeArray(?*classes.core.Node);
    analyzeArray(builtins.Variant);
    analyzeArray(Duration);

    analyzeDictionary(builtins.String, i32);
    analyzeDictionary(i32, builtins.String);
    analyzeDictionary(Duration, ?*classes.core.Node);
    analyzeDictionary(builtins.Variant, builtins.Variant);

    analyzeBuiltinTypedContainers();
    analyzePackedSlices();
}

comptime {
    checkConversionTypes();
    _ = &analyzeCoverage;
}

const godot = @import("godot");

const Conversion = godot.annotations.Conversion;
const builtins = godot.builtins;
const classes = godot.classes;
const collections = godot.collections;
const conversion = godot.internal.conversion;
const interface = godot.bindings.interface;
