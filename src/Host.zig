//! Represents an audio host.
//!
//! On most platforms, only one host is available. But some platforms (such as Linux), allow
//! multiple drivers to be installed and used, meaning that multiple hosts may be available.

const advice = @import("advice");
const std = @import("std");

const Self = @This();

/// The available devices on this host.
devices: []advice.Device,

/// The default output device.
default_output_device: ?*advice.Device,

/// The default input device.
default_input_device: ?*advice.Device,

/// Returns the default host for the current platform.
///
/// # Remarks
///
/// The returned host must be freed with `Host.deinit`.
pub inline fn default(allocator: std.mem.Allocator) advice.Error!Self {
    return advice.backend.defaultHost(allocator);
}

/// Frees the resources that were allocated for this host.
///
/// Once this function has been called, the host object may not be used anymore.
pub inline fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.devices) |*dev| dev.deinit(allocator);
    allocator.free(self.devices);
    self.* = undefined;
}
