//! Fixture `Node` for the live typed-container and owned-`Ref` property test.
//!
//! Exposes exported `Property` fields typed with the `godot.collections`
//! wrappers; the engine hint metadata derives from each wrapper's
//! `Element`/`Key`/`Value` declarations. `onInit` creates the wrappers, fills
//! them, and moves them into the property fields (the field owns the handle).
//! The `resource`/`resource_copy` fields exercise owned `ownership.Ref`
//! property storage, including a reference returned by a generated engine
//! method (`Resource.duplicate`) and a `Ref.take` probe that releases the taken
//! reference through the same helper `Ref.deinit` uses.

/// Node whose exported containers and owned resources are created at
/// instantiation time.
pub const LiveTypedNode = struct {
    pub const Extends = godot.classes.core.Node;

    base: godot.annotations.Base(Extends) = .{},

    /// Exported `Array[int]`; `onInit` stores `[1, 2, 3]`.
    numbers: godot.annotations.Property(godot.collections.Array(i32), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),

    /// Exported typed object array for `LiveResource` instances.
    resources: godot.annotations.Property(godot.collections.Array(?*LiveResource), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),

    /// Exported `Dictionary[String, int]`; `onInit` stores `{"kills": 3}`.
    scores: godot.annotations.Property(godot.collections.Dictionary(godot.builtins.String, i32), .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(undefined),

    /// Exported owned engine `Resource`; `onInit` stores a freshly constructed
    /// engine resource into the field. The field default exercises
    /// `ownership.Ref.empty` before the initializer replaces it.
    resource: godot.annotations.Property(ResourceRef, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(ResourceRef.empty),

    /// Exported owned engine `Resource` produced by a generated engine method:
    /// `Resource.duplicate` returns `ownership.Ref(Resource)`, which is moved
    /// straight into the property field.
    resource_copy: godot.annotations.Property(ResourceRef, .{
        .usage = .exported,
        .set = .best_effort,
        .deinit = .best_effort,
    }) = .init(ResourceRef.empty),

    pub const OnInit = godot.annotations.InitCallback(@This(), onInit);
    pub const OnDeinit = godot.annotations.DeinitCallback(@This(), onDeinit);

    pub fn onInit(self: *@This(), allocator: std.mem.Allocator, base: *Extends) void {
        _ = allocator;
        _ = base;

        // The wrapper is moved into the property field, which now owns the
        // handle; the local must not be deinitialized afterwards.
        var numbers = godot.collections.Array(i32).init();
        numbers.append(1);
        numbers.append(2);
        numbers.append(3);
        self.numbers.value = numbers;

        self.resources.value = godot.collections.Array(?*LiveResource).init();

        var scores = godot.collections.Dictionary(godot.builtins.String, i32).init();
        var key = godot.builtins.String.fromLatin1("kills");
        defer key.deinit();
        _ = scores.put(key, 3);
        self.scores.value = scores;

        // `construct` returns the creation reference in a `Ref`; the property
        // field takes that reference over, so the wrapper is moved, never
        // deinitialized locally.
        self.resource.value = godot.classes.core.Resource.construct();

        // Generated engine method returning an owned `Ref`: the returned
        // wrapper owns one reference, so it is moved into the second field.
        if (!self.resource.value.isNull()) {
            self.resource_copy.value = self.resource.value.get().?.duplicate(.{});

            // `take` moves a creation reference out of its wrapper; release it
            // through the helper `Ref.deinit` uses, destroying the probe
            // duplicate. Nothing is left behind at exit.
            var probe = self.resource.value.get().?.duplicate(.{});
            const probe_taken = probe.take();
            std.debug.assert(probe.isNull());
            godot.ownership.releaseRefCounted(?*godot.classes.core.Resource, probe_taken);
        }
    }

    /// Releases the container handles and owned references stored in the
    /// property fields.
    pub fn onDeinit(self: *@This(), allocator: std.mem.Allocator) void {
        _ = allocator;
        godot.annotations.deinitPropertyFields(@This(), self);
    }
};

const std = @import("std");

const godot = @import("godot");
const LiveResource = @import("live_resource.zig").LiveResource;

/// Owned reference stored by the `resource`/`resource_copy` properties; its
/// `empty` value is the field default before `onInit` stores a resource.
const ResourceRef = godot.ownership.Ref(godot.classes.core.Resource);
