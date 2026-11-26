//! Typed owning wrappers over the engine `Array` and `Dictionary` builtins.
//! Each wrapper owns one engine handle and is a declared conversion type whose
//! marker maps both paths to the engine builtin. Element conversion is lazy
//! (`get` returns `?T`), so a wrapper over an existing handle never verifies
//! element typing against the declared type.
//!
//! Variant conversion balances its engine reference. On the ptrcall path a
//! decoded wrapper owns one reference that the consumer releases through
//! `deinit`; methods and virtual callbacks rely on that contract.

/// A typed, owning `Array(T)` and a declared conversion type. The wrapper owns
/// `inner`; `deinit` releases it. Elements convert lazily through `conversion`,
/// and `Variant` elements leave the engine array untyped.
pub fn Array(comptime T: type) type {
    return struct {
        /// The owned engine handle; release it through this wrapper.
        inner: builtins.Array,

        const Self = @This();

        /// Declared element type; `annotations.property_hint` reads it to derive
        /// container hint metadata.
        pub const Element = T;

        /// The declared conversion: both paths use the engine `builtins.Array`.
        pub const GodotConversion = conversion_marker.Conversion(.{
            .engine = builtins.Array,
            .to_engine = convertToEngine,
            .from_engine = convertFromEngine,
        });

        pub fn init() Self {
            var self = Self{ .inner = builtins.Array.init() };
            self.initTyped();
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Adopts an owned engine array; the caller must not release it
        /// separately. The wrapper does not change its element typing.
        pub fn fromEngine(engine: builtins.Array) Self {
            return .{ .inner = engine };
        }

        /// Returns another owned handle to the same array. Engine arrays are
        /// reference types: mutations through either handle are visible to both,
        /// and each handle is released independently; use `clone` for a copy.
        pub fn toEngine(self: *const Self) builtins.Array {
            return builtins.Array.fromArray(self.inner);
        }

        /// Returns a new wrapper over an independent shallow copy of the outer
        /// array; nested containers and objects stay shared.
        pub fn clone(self: *const Self) Self {
            return .{ .inner = self.inner.duplicate(.{}) };
        }

        pub fn len(self: *const Self) usize {
            return @intCast(self.inner.size());
        }

        pub fn append(self: *Self, value: T) void {
            var element: builtins.Variant = undefined;
            conversion.encodeVariant(T, value, &element);
            defer element.deinit();
            self.inner.append(element);
        }

        pub fn get(self: *const Self, index: usize) ?T {
            var element = self.inner.get(@intCast(index));
            defer element.deinit();
            return conversion.decodeVariant(T, &element);
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            var element: builtins.Variant = undefined;
            conversion.encodeVariant(T, value, &element);
            defer element.deinit();
            self.inner.set(@intCast(index), element);
        }

        /// Conversion adapter: `toEngine` taking the wrapper by value, as the
        /// marker requires.
        fn convertToEngine(self: Self) builtins.Array {
            return builtins.Array.fromArray(self.inner);
        }

        /// Conversion adapter: retains a reference, so the decoded wrapper owns
        /// its handle; only the ptrcall value is borrowed.
        fn convertFromEngine(engine: builtins.Array) Self {
            return .{ .inner = builtins.Array.fromArray(engine) };
        }

        /// The engine only accepts `set_typed` on an empty, uniquely referenced
        /// array, so it runs before the wrapper is returned.
        fn initTyped(self: *Self) void {
            conversion.checkSupported(T, .variant, "godot.collections.Array element");
            if (comptime T == builtins.Variant) return;

            const variant_type = comptime conversion.variantType(T) orelse return;
            if (comptime variant_type == .object) {
                const class_name =
                    builtins.StringName.fromComptimeLatin1(conversion.engineClassName(T));
                self.inner.setTypedAs(variant_type, &class_name, null);
                return;
            }
            self.inner.setTypedAs(variant_type, null, null);
        }
    };
}

/// A typed, owning `Dictionary(K, V)` and a declared conversion type. The
/// wrapper owns `inner`; `deinit` releases it. A `Variant` key or value side
/// stays untyped.
pub fn Dictionary(comptime K: type, comptime V: type) type {
    return struct {
        /// The owned engine handle; release it through this wrapper.
        inner: builtins.Dictionary,

        const Self = @This();

        /// Declared key type; `annotations.property_hint` reads it to derive
        /// container hint metadata.
        pub const Key = K;
        /// Declared value type; `annotations.property_hint` reads it to derive
        /// container hint metadata.
        pub const Value = V;

        /// The declared conversion: both paths use the engine `builtins.Dictionary`.
        pub const GodotConversion = conversion_marker.Conversion(.{
            .engine = builtins.Dictionary,
            .to_engine = convertToEngine,
            .from_engine = convertFromEngine,
        });

        pub fn init() Self {
            var self = Self{ .inner = builtins.Dictionary.init() };
            self.initTyped();
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Adopts an owned engine dictionary; the caller must not release it
        /// separately. The wrapper does not change its side typing.
        pub fn fromEngine(engine: builtins.Dictionary) Self {
            return .{ .inner = engine };
        }

        /// Returns another owned handle to the same dictionary. Engine
        /// dictionaries are reference types: mutations through either handle are
        /// visible to both, and each handle is released independently; use
        /// `clone` for a copy.
        pub fn toEngine(self: *const Self) builtins.Dictionary {
            return builtins.Dictionary.fromDictionary(self.inner);
        }

        /// Returns a new wrapper over an independent shallow copy of the outer
        /// dictionary; nested containers and objects stay shared.
        pub fn clone(self: *const Self) Self {
            return .{ .inner = self.inner.duplicate(.{}) };
        }

        pub fn len(self: *const Self) usize {
            return @intCast(self.inner.size());
        }

        pub fn put(self: *Self, key: K, value: V) bool {
            var key_variant: builtins.Variant = undefined;
            conversion.encodeVariant(K, key, &key_variant);
            defer key_variant.deinit();
            var value_variant: builtins.Variant = undefined;
            conversion.encodeVariant(V, value, &value_variant);
            defer value_variant.deinit();
            return self.inner.set(key_variant, value_variant);
        }

        pub fn get(self: *const Self, key: K) ?V {
            var key_variant: builtins.Variant = undefined;
            conversion.encodeVariant(K, key, &key_variant);
            defer key_variant.deinit();
            var value = self.inner.get(key_variant, .{});
            defer value.deinit();
            return conversion.decodeVariant(V, &value);
        }

        pub fn contains(self: *const Self, key: K) bool {
            var key_variant: builtins.Variant = undefined;
            conversion.encodeVariant(K, key, &key_variant);
            defer key_variant.deinit();
            return self.inner.has(key_variant);
        }

        pub fn erase(self: *Self, key: K) bool {
            var key_variant: builtins.Variant = undefined;
            conversion.encodeVariant(K, key, &key_variant);
            defer key_variant.deinit();
            return self.inner.erase(key_variant);
        }

        /// Conversion adapter: `toEngine` taking the wrapper by value, as the
        /// marker requires.
        fn convertToEngine(self: Self) builtins.Dictionary {
            return builtins.Dictionary.fromDictionary(self.inner);
        }

        /// Conversion adapter: retains a reference, so the decoded wrapper owns
        /// its handle; only the ptrcall value is borrowed.
        fn convertFromEngine(engine: builtins.Dictionary) Self {
            return .{ .inner = builtins.Dictionary.fromDictionary(engine) };
        }

        /// The engine only accepts `set_typed` on an empty, uniquely referenced
        /// dictionary, so it runs before the wrapper is returned; an untyped
        /// side passes no type and two untyped sides skip the call.
        fn initTyped(self: *Self) void {
            conversion.checkSupported(K, .variant, "godot.collections.Dictionary key");
            conversion.checkSupported(V, .variant, "godot.collections.Dictionary value");
            if (comptime K == builtins.Variant and V == builtins.Variant) return;

            const key_type = comptime (conversion.variantType(K) orelse .nil);
            const value_type = comptime (conversion.variantType(V) orelse .nil);
            const key_class_name =
                builtins.StringName.fromComptimeLatin1(conversion.engineClassName(K));
            const value_class_name =
                builtins.StringName.fromComptimeLatin1(conversion.engineClassName(V));
            self.inner.setTypedAs(
                key_type,
                if (comptime key_type == .object) &key_class_name else null,
                null,
                value_type,
                if (comptime value_type == .object) &value_class_name else null,
                null,
            );
        }
    };
}

const builtins = @import("builtins/builtins.zig");
const conversion = @import("conversion.zig");
const conversion_marker = @import("annotations/conversion.zig");
