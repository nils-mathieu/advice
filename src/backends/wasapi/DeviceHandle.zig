const sys = @import("sys.zig");
const advice = @import("advice");
const std = @import("std");
const util = @import("utility.zig");

const Self = @This();

/// The audio device object itself.
obj: *sys.IMMDevice,
/// The audio client associated with the device.
audio_client: *sys.IAudioClient,

/// Creates a new `DeviceHandle` from the provided device object.
///
/// # Notes
///
/// This function will release the provided device object, *even if it fails*.
pub fn fromHandle(dev: *sys.IMMDevice) advice.Error!Self {
    errdefer _ = dev.IUnknown.Release();

    var audio_client: *sys.IAudioClient = undefined;
    try util.checkResult(dev.Activate(
        sys.IID_IAudioClient,
        sys.CLSCTX_ALL,
        null,
        @ptrCast(&audio_client),
    ));
    errdefer _ = audio_client.IUnknown.Release();

    return Self{
        .obj = dev,
        .audio_client = audio_client,
    };
}

/// Deinitializes the default handle.
pub fn deinit(self: *Self) void {
    _ = self.audio_client.IUnknown.Release();
    _ = self.obj.IUnknown.Release();
}

/// Returns the default device for the specified data flow.
pub fn default(e: *const sys.IMMDeviceEnumerator, data_flow: sys.EDataFlow) advice.Error!Self {
    var device: *sys.IMMDevice = undefined;
    try util.checkResult(e.GetDefaultAudioEndpoint(data_flow, sys.eConsole, @ptrCast(&device)));
    return Self.fromHandle(device);
}

/// Returns the ID of an audio device.
///
/// The result must be freed with `CoTaskMemFree`.
pub fn getId(self: Self) advice.Error![]u16 {
    var id: ?sys.PWSTR = undefined;
    try util.checkResult(self.obj.GetId(&id));
    if (id == null) {
        if (util.should_log_errors) std.log.err("advice: Device ID is null", .{});
        return error.OsError;
    }
    return std.mem.span(id.?);
}

/// Gets the name of the device.
pub fn getDataFlow(self: Self) advice.Error!sys.EDataFlow {
    var endpoint: *sys.IMMEndpoint = undefined;
    try util.checkResult(self.obj.IUnknown.QueryInterface(sys.IID_IMMEndpoint, @ptrCast(&endpoint)));
    defer _ = endpoint.IUnknown.Release();

    var data_flow: sys.EDataFlow = undefined;
    try util.checkResult(endpoint.GetDataFlow(&data_flow));

    return data_flow;
}

/// Returns whether the device supports a particular wave format.
pub fn supportsWaveFormat(self: Self, format: *const sys.WAVEFORMATEX, closest_match: ?*?sys.WAVEFORMATEX) advice.Error!bool {
    var closest_match_handle: ?*sys.WAVEFORMATEX = null;

    const result = self.audio_client.IsFormatSupported(
        sys.AUDCLNT_SHAREMODE_SHARED, // TODO: exclusive-mode
        format,
        @ptrCast(&closest_match_handle),
    );
    if (closest_match_handle != null) {
        if (closest_match) |dst| dst.* = closest_match_handle.?.*;
        sys.CoTaskMemFree(closest_match_handle.?);
    } else {
        if (closest_match) |dst| dst.* = null;
    }

    switch (result) {
        sys.S_FALSE, sys.AUDCLNT_E_UNSUPPORTED_FORMAT => return false,
        sys.S_OK => return true,
        else => {
            std.debug.print("{}\n", .{format});
            if (util.should_log_errors) std.log.err("advice: WASAPI error: {d}", .{result});
            return error.OsError;
        },
    }
}

/// Attempts to get the audio client as an `IAudioClient2`.
///
/// The result must be released with `IUnknown.Release`.
pub fn tryAudioClient2(self: Self) ?*sys.IAudioClient2 {
    var audio_client2: *sys.IAudioClient2 = undefined;
    if (self.audio_client.IUnknown.QueryInterface(
        sys.IID_IAudioClient2,
        @ptrCast(&audio_client2),
    ) == sys.S_OK) {
        return audio_client2;
    } else {
        return null;
    }
}

/// Gets the buffer size limits for the device.
///
/// Note that the resulting buffer sizes are in 100-nanosecond units (WTF).
pub fn getBufferSizeLimits(self: Self, format: *const sys.WAVEFORMATEX) advice.Error!?[2]u64 {
    var audio_client2 = self.tryAudioClient2() orelse return null;
    defer _ = audio_client2.IUnknown.Release();

    var min: i64 = undefined;
    var max: i64 = undefined;
    const result = audio_client2.GetBufferSizeLimits(format, 1, &min, &max);
    switch (result) {
        sys.AUDCLNT_E_OFFLOAD_MODE_ONLY => return null,
        sys.S_OK => {},
        else => {
            if (util.should_log_errors) std.log.warn("advice: Failed to get buffer size limits: {d}", .{result});
            return error.OsError;
        },
    }

    if (min < 0 or max < 0) {
        if (util.should_log_errors) std.log.warn("advice: Invalid buffer size limits detected: {d}, {d}", .{ min, max });
        return error.OsError;
    }

    return .{ @as(u64, @intCast(min)), @as(u64, @intCast(max)) };
}

/// Finds which sample rates are supported by the device.
pub fn getSupportedSampleRates(
    self: Self,
    allocator: std.mem.Allocator,
    format: *sys.WAVEFORMATEX,
) advice.Error![]u32 {
    const tested_sample_rates = [_]u32{ 8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000, 192000 };

    var sample_rates = std.ArrayListUnmanaged(u32){};
    errdefer sample_rates.deinit(allocator);

    for (tested_sample_rates) |rate| {
        format.nSamplesPerSec = rate;
        format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;

        var closest_match: ?sys.WAVEFORMATEX = null;
        if (try self.supportsWaveFormat(format, &closest_match)) {
            if (std.mem.indexOfScalar(u32, sample_rates.items, rate) == null)
                try sample_rates.append(allocator, rate);
        } else if (closest_match) |cm| {
            const sr = cm.nSamplesPerSec;
            if (std.mem.indexOfScalar(u32, sample_rates.items, sr) == null)
                try sample_rates.append(allocator, cm.nSamplesPerSec);
        }
    }

    return sample_rates.toOwnedSlice(allocator);
}

/// Gets the available input configurations for a device.
pub fn getAvailableConfigs(
    self: Self,
    allocator: std.mem.Allocator,
) advice.Error!?advice.Device.AvailableConfigs {
    var waveformat: *sys.WAVEFORMATEX = undefined;
    try util.checkResult(self.audio_client.GetMixFormat(@ptrCast(&waveformat)));
    defer _ = sys.CoTaskMemFree(waveformat);

    if (!try self.supportsWaveFormat(waveformat, null)) {
        // The device does not support its default format? That's weird, and we can't really
        // do anything with that.
        return null;
    }

    var buffer_size: ?[2]u32 = null;
    if (try self.getBufferSizeLimits(waveformat)) |dur| {
        const sample_rate: u64 = waveformat.nSamplesPerSec;

        const min = std.math.cast(u32, dur[0] * sample_rate / (std.time.ns_per_s / 100));
        const max = std.math.cast(u32, dur[1] * sample_rate / (std.time.ns_per_s / 100));
        if (min != null and max != null) buffer_size = .{ min.?, max.? };
    }

    const og_sample_rate = waveformat.nSamplesPerSec;
    const og_channel_count = waveformat.nChannels;

    const sample_rates = try self.getSupportedSampleRates(allocator, waveformat);
    errdefer allocator.free(sample_rates);

    // There is no method to query the available formats, but we try and change the default
    // one and save which ones are supported.
    var formats = advice.Device.AvailableConfigs.Formats{};
    for (advice.Stream.Format.all) |format| {
        if (util.makeWaveFormat(format, og_sample_rate, og_channel_count)) |wf| {
            if (try self.supportsWaveFormat(&wf, null))
                formats.insert(format);
        }
    }

    return advice.Device.AvailableConfigs{
        .sample_rates = sample_rates,
        .buffer_size = buffer_size,
        .channel_count = waveformat.nChannels,
        .formats = formats,
        .channel_format = .interleaved,
    };
}

/// Returns the name of an audio device.
///
/// The result must be freed with `allocator.free`.
pub fn getName(self: Self, allocator: std.mem.Allocator) advice.Error![]u8 {
    var property_store: *sys.IPropertyStore = undefined;
    try util.checkResult(self.obj.OpenPropertyStore(sys.STGM_READ, @ptrCast(&property_store)));
    defer _ = property_store.IUnknown.Release();

    var friendly_name: sys.PROPVARIANT = undefined;
    try util.checkResult(property_store.GetValue(@ptrCast(&sys.DEVPKEY_Device_FriendlyName), &friendly_name));
    defer _ = sys.PropVariantClear(&friendly_name);

    if (friendly_name.Anonymous.Anonymous.vt != @intFromEnum(sys.VT_LPWSTR)) {
        if (util.should_log_errors) std.log.err("advice: Device friendly name is not a string: {d}", .{friendly_name.Anonymous.Anonymous.vt});
        return error.OsError;
    }

    const utf16_ptr: [*:0]u16 = friendly_name.Anonymous.Anonymous.Anonymous.pwszVal orelse {
        if (util.should_log_errors) std.log.err("advice: Device friendly name is null", .{});
        return error.OsError;
    };
    const utf16_data: []u16 = std.mem.span(utf16_ptr);

    const utf8_data = std.unicode.utf16LeToUtf8Alloc(allocator, utf16_data) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            if (util.should_log_errors) std.log.err("advice: Failed to convert UTF-16 name to UTF-8", .{});
            return error.OsError;
        },
    };
    errdefer allocator.free(utf8_data);

    return utf8_data;
}

/// Gets the buffer size of the audio device.
pub fn getBufferSize(self: Self) advice.Error!u32 {
    var frames: u32 = undefined;
    try util.checkResult(self.audio_client.GetBufferSize(&frames));
    return frames;
}

/// Gets the current padding of the audio device.
pub fn getCurrentPadding(self: Self) advice.Error!u32 {
    var padding: u32 = undefined;
    try util.checkResult(self.audio_client.GetCurrentPadding(&padding));
    return padding;
}
