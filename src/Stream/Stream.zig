//! An open audio stream.

const advice = @import("advice");
const std = @import("std");

const Self = @This();

pub const Config = @import("Config.zig");
pub const Format = @import("Format.zig").Format;

/// The platform-specific stream implementation.
impl: advice.backend.Stream,

/// Opens an output stream for the provided device.
///
/// # Requirements
///
/// This function may only be called if an `output_config` is available for the device.
///
/// # Returns
///
/// This function returns the open stream. It must be closed with `Stream.close` when it is no
/// longer needed.
pub fn openOutput(
    device: *const advice.Device,
    allocator: std.mem.Allocator,
    config: Config,
) advice.Error!Self {
    return Self{ .impl = try advice.backend.Stream.openOutput(device, allocator, config) };
}

/// Opens an input stream for the device.
///
/// # Requirements
///
/// This function may only be called if an `input_config` is available for the device.
///
/// # Returns
///
/// This function returns the open stream. It must be closed with `Stream.close` when it is no
/// longer needed.
pub fn openInput(
    device: advice.Device,
    allocator: std.mem.Allocator,
    config: Config,
) advice.Error!Self {
    return Self{ .impl = try advice.backend.Stream.openInput(device, allocator, config) };
}

/// Converts the provided data pointer to the correct type.
///
/// This is a convenience function to avoid making mistakes when converting the raw `*anyopaque`
/// pointer into the correct type for output streams.
pub fn getOutputCallbackData(
    comptime SampleFormat: type,
    comptime channel_format: advice.Device.AvailableConfigs.ChannelFormat,
    data: *anyopaque,
    channel_count: u32,
    frame_count: usize,
) switch (channel_format) {
    .interleaved => []SampleFormat,
    .non_interleaved => []const [*]SampleFormat,
} {
    switch (channel_format) {
        .interleaved => return @as([*]SampleFormat, @alignCast(@ptrCast(data)))[0 .. frame_count * channel_count],
        .non_interleaved => return @as([*]const [*]SampleFormat, @alignCast(@ptrCast(data)))[0..channel_count],
    }
}

/// Converts the provided data pointer to the correct type.
///
/// This is a convenience function to avoid making mistakes when converting the raw `*anyopaque`
/// pointer into the correct type for input streams.
pub fn getInputCallbackData(
    comptime SampleFormat: type,
    comptime channel_format: advice.Device.AvailableConfigs.ChannelFormat,
    data: *anyopaque,
    channel_count: u32,
    frame_count: usize,
) switch (channel_format) {
    .interleaved => []const SampleFormat,
    .non_interleaved => []const [*]const SampleFormat,
} {
    switch (channel_format) {
        .interleaved => return @as([*]const SampleFormat, @alignCast(@ptrCast(data)))[0 .. frame_count * channel_count],
        .non_interleaved => return @as([*]const [*]const SampleFormat, @alignCast(@ptrCast(data)))[0..channel_count],
    }
}

/// Closes the stream.
pub fn close(self: *Self, allocator: std.mem.Allocator) void {
    self.impl.close(allocator);
}

/// Starts the stream.
pub fn play(self: *Self) advice.Error!void {
    try self.impl.play();
}

/// Pauses the stream, potentially saving energy and CPU usage while it's not needed.
pub fn pause(self: *Self) advice.Error!void {
    try self.impl.pause();
}
