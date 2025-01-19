//! The WASAPI (Windows Audio Session API) backend for the Advice library.

const std = @import("std");
const advice = @import("advice");
const sys = @import("sys.zig");
const util = @import("utility.zig");

pub const Stream = @import("Stream.zig");
pub const DeviceHandle = @import("DeviceHandle.zig");

pub const DeviceData = struct {
    device: DeviceHandle,

    pub fn deinit(self: *DeviceData, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.device.deinit();
    }
};

/// Gets the ID of a particular default device (for the given data flow).
fn getDefaultDeviceId(device_enumerator: *sys.IMMDeviceEnumerator, data_flow: sys.EDataFlow) advice.Error![]u16 {
    var device: *sys.IMMDevice = undefined;
    try util.checkResult(device_enumerator.GetDefaultAudioEndpoint(data_flow, sys.eMultimedia, @ptrCast(&device)));
    defer _ = device.IUnknown.Release();

    var id: ?sys.PWSTR = undefined;
    try util.checkResult(device.GetId(&id));

    if (id == null) {
        if (util.should_log_errors) std.log.err("advice: Device ID is null", .{});
        return error.OsError;
    }

    return std.mem.span(id.?);
}

/// See `advice.Host.default`.
pub fn defaultHost(allocator: std.mem.Allocator) advice.Error!advice.Host {
    @import("com.zig").ensureComInitialized();

    var device_enumerator: *sys.IMMDeviceEnumerator = undefined;
    try util.checkResult(sys.CoCreateInstance(
        sys.CLSID_MMDeviceEnumerator,
        null,
        sys.CLSCTX_ALL,
        sys.IID_IMMDeviceEnumerator,
        @ptrCast(&device_enumerator),
    ));
    defer _ = device_enumerator.IUnknown.Release();

    var device_collection: *sys.IMMDeviceCollection = undefined;
    try util.checkResult(device_enumerator.EnumAudioEndpoints(
        sys.eAll,
        sys.DEVICE_STATE_ACTIVE,
        @ptrCast(&device_collection),
    ));
    defer _ = device_collection.IUnknown.Release();

    var device_count: u32 = undefined;
    try util.checkResult(device_collection.GetCount(&device_count));

    var devices = try std.ArrayListUnmanaged(advice.Device).initCapacity(allocator, device_count);
    errdefer devices.deinit(allocator);

    const default_output_device_id = try getDefaultDeviceId(device_enumerator, sys.eRender);
    defer _ = sys.CoTaskMemFree(default_output_device_id.ptr);

    const default_input_device_id = try getDefaultDeviceId(device_enumerator, sys.eCapture);
    defer _ = sys.CoTaskMemFree(default_input_device_id.ptr);

    var default_output_device_index: ?usize = null;
    var default_input_device_index: ?usize = null;

    for (0..device_count) |i| {
        var device_handle: *sys.IMMDevice = undefined;
        try util.checkResult(device_collection.Item(@intCast(i), @ptrCast(&device_handle)));
        var device = try DeviceHandle.fromHandle(device_handle);
        errdefer device.deinit();

        const name = try device.getName(allocator);
        errdefer allocator.free(name);

        const id = try device.getId();
        defer sys.CoTaskMemFree(id.ptr);

        if (std.mem.eql(u16, default_output_device_id, id)) {
            default_output_device_index = i;
        }
        if (std.mem.eql(u16, default_input_device_id, id)) {
            default_input_device_index = i;
        }

        var input_configs: ?advice.Device.AvailableConfigs = null;
        var output_configs: ?advice.Device.AvailableConfigs = null;

        switch (try device.getDataFlow()) {
            sys.eRender => output_configs = try device.getAvailableConfigs(allocator),
            sys.eCapture => input_configs = try device.getAvailableConfigs(allocator),
            else => {},
        }

        try devices.append(allocator, advice.Device{
            .input_configs = input_configs,
            .output_configs = output_configs,
            .name = name,
            .data = .{ .device = device },
        });
    }
    errdefer for (devices.items) |*dev| dev.deinit(allocator);

    const devices_slice = try devices.toOwnedSlice(allocator);
    return advice.Host{
        .default_input_device = if (default_input_device_index) |i| &devices_slice[i] else null,
        .default_output_device = if (default_output_device_index) |i| &devices_slice[i] else null,
        .devices = devices_slice,
    };
}
