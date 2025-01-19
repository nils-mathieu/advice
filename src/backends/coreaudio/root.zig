const advice = @import("advice");
const std = @import("std");
const Allocator = std.mem.Allocator;
const sys = @import("sys.zig");
const builtin = @import("builtin");
const util = @import("utility.zig");
const DeviceId = @import("DeviceId.zig");

pub const Stream = @import("Stream.zig");

/// The device data associated with an audio device on the CoreAudio platform.
pub const DeviceData = struct {
    /// The ID of the device,
    id: DeviceId,
    /// Some flags associated with the device.
    flags: packed struct {
        /// Whether the device is the default input device.
        default_input: bool = false,
        /// Whether the device is the default output device.
        default_output: bool = false,
    },

    pub inline fn deinit(self: *DeviceData, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }
};

/// Returns the default (and only) host for the CoreAudio platform.
pub fn defaultHost(a: Allocator) advice.Error!advice.Host {
    const device_ids = try DeviceId.enumerate(a);
    defer a.free(device_ids);

    var devices_buf = try std
        .ArrayListUnmanaged(advice.Device)
        .initCapacity(a, device_ids.len);
    errdefer devices_buf.deinit(a);

    for (device_ids) |id| {
        const name = try id.getName(a);
        errdefer a.free(name);

        var output_configs = try id.getAvailableOutputConfigs(a);
        errdefer if (output_configs) |*c| c.deinit(a);

        var input_configs = try id.getAvailableInputConfigs(a);
        errdefer if (input_configs) |*c| c.deinit(a);

        try devices_buf.append(a, advice.Device{
            .name = name,
            .output_configs = output_configs,
            .input_configs = input_configs,
            .data = .{
                .id = id,
                .flags = .{},
            },
        });
    }
    errdefer for (devices_buf.items) |*dev| dev.deinit(a);

    const default_output_device_id = DeviceId.getDefaultOutputDevice();
    const default_input_device_id = DeviceId.getDefaultInputDevice();

    var default_output_device: ?*advice.Device = null;
    var default_input_device: ?*advice.Device = null;

    for (devices_buf.items) |*dev| {
        if (default_output_device_id != null and dev.data.id.raw == default_output_device_id.?.raw) {
            default_output_device = dev;
            dev.data.flags.default_output = true;
        }
        if (default_input_device_id != null and dev.data.id.raw == default_input_device_id.?.raw) {
            default_input_device = dev;
            dev.data.flags.default_input = true;
        }
    }

    return advice.Host{
        .devices = try devices_buf.toOwnedSlice(a),
        .default_input_device = default_input_device,
        .default_output_device = default_output_device,
    };
}
