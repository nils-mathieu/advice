//! Represents a device available on some host.

const std = @import("std");
const advice = @import("advice");

const Self = @This();

pub const AvailableConfigs = @import("AvailableConfigs.zig");

/// The available configurations for the device as an input device.
input_configs: ?AvailableConfigs,

/// The available configurations for the device as an output device.
output_configs: ?AvailableConfigs,

/// The name of the device.
name: []u8,

/// The data associated with the device.
data: advice.backend.DeviceData,

/// Frees the resources associated with the output device.
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    if (self.output_configs) |*c| c.deinit(allocator);
    if (self.input_configs) |*c| c.deinit(allocator);
    self.data.deinit(allocator);
    self.* = undefined;
}
