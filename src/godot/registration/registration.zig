//! Registration-layer public surface.

pub const Registry = @import("Registry.zig");
pub const ClassOptions = Registry.ClassOptions;

pub const ClassRegistration = @import("ClassRegistration.zig");

pub const instance = @import("instance.zig");
pub const notification = @import("notification.zig");
pub const property = @import("property.zig");
pub const virtuals = @import("virtuals.zig");
pub const classdb = @import("classdb.zig");

pub const PostRegistrationCallback = classdb.PostRegistrationCallback;

pub const CreateInstance = instance.CreateInstance;
pub const RecreateInstance = instance.RecreateInstance;
pub const FreeInstance = instance.FreeInstance;
pub const Notification = notification.Notification;
