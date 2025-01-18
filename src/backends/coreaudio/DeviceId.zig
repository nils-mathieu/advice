//! Represents audio device ID on the CoreAudio platform.

const sys = @import("sys.zig");
const std = @import("std");
const builtin = @import("builtin");
const advice = @import("advice");
const util = @import("utility.zig");

const Self = @This();

/// The Id of the audio device.
raw: sys.AudioDeviceID,

// Make sure that our wrapper struct is transparent.
comptime {
    std.debug.assert(@sizeOf(Self) == @sizeOf(sys.AudioDeviceID));
    std.debug.assert(@alignOf(Self) == @alignOf(sys.AudioDeviceID));
}

/// A possible property scope for the device.
pub const Scope = enum(sys.AudioObjectPropertyScope) {
    input = sys.kAudioObjectPropertyScopeInput,
    output = sys.kAudioObjectPropertyScopeOutput,
    global = sys.kAudioObjectPropertyScopeGlobal,
};

/// Gets the default input or output device.
fn getDefaultDevice(selector: sys.AudioObjectPropertySelector) ?Self {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = selector,
        .mScope = sys.kAudioObjectPropertyScopeGlobal,
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var device_id: sys.AudioDeviceID = 0;
    var data_size: sys.UInt32 = @sizeOf(sys.AudioDeviceID);

    if (sys.AudioObjectGetPropertyData(
        sys.kAudioObjectSystemObject,
        &property_address,
        0,
        null,
        &data_size,
        &device_id,
    ) != sys.kAudioHardwareNoError) {
        return null;
    }

    return Self{ .raw = device_id };
}

/// Returns the default output device ID.
pub inline fn getDefaultOutputDevice() ?Self {
    return Self.getDefaultDevice(sys.kAudioHardwarePropertyDefaultOutputDevice);
}

/// Returns the default input device ID.
pub inline fn getDefaultInputDevice() ?Self {
    return Self.getDefaultDevice(sys.kAudioHardwarePropertyDefaultInputDevice);
}

/// Enumerates the device IDs for all available devices.
///
/// The result must be freed by the caller.
pub fn enumerate(allocator: std.mem.Allocator) advice.Error![]Self {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioHardwarePropertyDevices,
        .mScope = sys.kAudioObjectPropertyScopeGlobal,
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: u32 = 0;
    if (sys.AudioObjectGetPropertyDataSize(
        sys.kAudioObjectSystemObject,
        &property_address,
        0,
        null,
        &data_size,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    if (data_size % @sizeOf(sys.AudioDeviceID) != 0) {
        return error.OsError;
    }

    const device_count = data_size / @sizeOf(Self);
    const devices = try allocator.alloc(Self, device_count);

    if (sys.AudioObjectGetPropertyData(
        sys.kAudioObjectSystemObject,
        &property_address,
        0,
        null,
        &data_size,
        devices.ptr,
    ) != 0) {
        return error.OsError;
    }

    return devices;
}

/// Queries the name of the device.
///
/// The resulting string must be freed by the caller.
pub fn getName(self: Self, allocator: std.mem.Allocator) advice.Error![]u8 {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyDeviceNameCFString,
        .mScope = sys.kAudioObjectPropertyScopeOutput,
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var device_name: sys.CFStringRef = null;
    var data_size: sys.UInt32 = @sizeOf(sys.CFStringRef);

    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
        @ptrCast(&device_name),
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }
    defer sys.CFRelease(device_name);

    return util.extractCFString(device_name, allocator);
}

/// Gets the buffer list for the device.
///
/// The returned slice list must be freed by the user.
pub fn getBufferList(
    self: Self,
    scope: Scope,
    allocator: std.mem.Allocator,
    output: *[]sys.AudioBuffer,
) advice.Error![]align(@alignOf(sys.AudioBufferList)) u8 {
    var property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyStreamConfiguration,
        .mScope = @intFromEnum(scope),
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: sys.UInt32 = 0;
    if (sys.AudioObjectGetPropertyDataSize(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    const buffer_bytes = try allocator.alignedAlloc(
        u8,
        @alignOf(sys.AudioBufferList),
        data_size,
    );
    errdefer allocator.free(buffer_bytes);

    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
        buffer_bytes.ptr,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    const buffer_list: *sys.AudioBufferList = @ptrCast(buffer_bytes.ptr);
    output.* = (@as([*]sys.AudioBuffer, &buffer_list.mBuffers))[0..buffer_list.mNumberBuffers];

    return buffer_bytes;
}

/// Gets the available sample rates for the device.
///
/// The returned pointer must be freed by the user.
pub fn getAvailableSampleRates(
    self: Self,
    scope: Scope,
    allocator: std.mem.Allocator,
) advice.Error![]sys.AudioValueRange {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyAvailableNominalSampleRates,
        .mScope = @intFromEnum(scope),
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: sys.UInt32 = 0;
    if (sys.AudioObjectGetPropertyDataSize(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }
    if (data_size % @sizeOf(sys.AudioValueRange) != 0) return error.OsError;

    const sample_rate_ranges = try allocator.alloc(sys.AudioValueRange, data_size / @sizeOf(sys.AudioValueRange));
    errdefer allocator.free(sample_rate_ranges);

    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
        sample_rate_ranges.ptr,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    return sample_rate_ranges;
}

/// Gets the available basic descriptions for the device.
pub fn getAvailableBasicDescs(
    self: Self,
    allocator: std.mem.Allocator,
    scope: Scope,
) advice.Error![]sys.AudioStreamBasicDescription {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyStreamFormats,
        .mScope = @intFromEnum(scope),
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: sys.UInt32 = 0;
    if (sys.AudioObjectGetPropertyDataSize(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    if (data_size % @sizeOf(sys.AudioStreamBasicDescription) != 0) {
        return error.OsError;
    }

    const basic_descs = try allocator.alloc(sys.AudioStreamBasicDescription, data_size / @sizeOf(sys.AudioStreamBasicDescription));
    errdefer allocator.free(basic_descs);

    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
        basic_descs.ptr,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    return basic_descs;
}

/// Gets the available formats for the device.
pub fn getAvailableFormats(
    self: Self,
    allocator: std.mem.Allocator,
    scope: Scope,
) advice.Error!advice.Device.AvailableConfigs.Formats {
    const descs = try self.getAvailableBasicDescs(allocator, scope);
    defer allocator.free(descs);

    var formats = advice.Device.AvailableConfigs.Formats{};

    for (descs) |desc| {
        if (desc.mFormatID != sys.kAudioFormatLinearPCM) {
            continue;
        }

        if (desc.mFormatFlags & sys.kAudioFormatFlagIsPacked == 0) {
            continue;
        }

        if (desc.mFormatFlags & sys.kAudioFormatFlagIsFloat != 0) {
            switch (desc.mBitsPerChannel) {
                32 => formats.f32 = true,
                64 => formats.f64 = true,
                else => {},
            }
        } else if (desc.mFormatFlags & sys.kAudioFormatFlagIsSignedInteger != 0) {
            switch (desc.mBitsPerChannel) {
                8 => formats.i8 = true,
                16 => formats.i16 = true,
                24 => formats.i24 = true,
                32 => formats.i32 = true,
                64 => formats.i64 = true,
                else => {},
            }
        } else {
            switch (desc.mBitsPerChannel) {
                8 => formats.u8 = true,
                16 => formats.u16 = true,
                24 => formats.u24 = true,
                32 => formats.u32 = true,
                64 => formats.u64 = true,
                else => {},
            }
        }
    }

    return formats;
}

pub fn getBufferSizeRange(self: Self, scope: Scope) advice.Error!sys.AudioValueRange {
    const property_address = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyBufferFrameSizeRange,
        .mScope = @intFromEnum(scope),
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: sys.UInt32 = @sizeOf(sys.AudioValueRange);
    var buffer_size_range: sys.AudioValueRange = undefined;
    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_address,
        0,
        null,
        &data_size,
        &buffer_size_range,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    return buffer_size_range;
}

/// Gets the configurations associated with the device, for a particular scope.
pub fn getAvailableConfigs(
    self: Self,
    allocator: std.mem.Allocator,
    scope: Scope,
) advice.Error!?advice.Device.AvailableConfigs {
    var buffers: []sys.AudioBuffer = undefined;
    const buffers_bytes = try self.getBufferList(scope, allocator, &buffers);
    defer allocator.free(buffers_bytes);

    if (buffers.len == 0) return null;
    if (buffers.len != 1) {
        if (builtin.mode == .Debug) {
            std.log.warn("advice: Ignoring device with multiple buffers ({d})", .{buffers.len});
        }
        return null;
    }
    const channel_count = buffers[0].mNumberChannels;
    if (channel_count == 0) return null;

    const sample_rate_ranges = try self.getAvailableSampleRates(scope, allocator);
    defer allocator.free(sample_rate_ranges);

    var sample_rates = std.ArrayListUnmanaged(u32){};
    errdefer sample_rates.deinit(allocator);

    for (sample_rate_ranges) |range| {
        if (range.mMinimum != range.mMaximum) {
            if (builtin.mode == .Debug) {
                std.log.warn("advice: Ignoring sampling range - min != max (min: {d}, max: {d})", .{ range.mMinimum, range.mMaximum });
            }
            continue;
        }

        if (!util.isInteger(range.mMinimum)) {
            if (builtin.mode == .Debug) {
                std.log.warn("advice: Ignoring sampling range - non-integer value ({d})", .{range.mMinimum});
            }
            continue;
        }

        const sample_rate: u32 = @intFromFloat(@trunc(range.mMinimum));
        try sample_rates.append(allocator, sample_rate);
    }

    const formats = try self.getAvailableFormats(allocator, scope);
    if (formats.isEmpty()) return null;

    const buffer_size_range = try self.getBufferSizeRange(scope);
    if (!util.isInteger(buffer_size_range.mMinimum) or !util.isInteger(buffer_size_range.mMaximum)) {
        if (builtin.mode == .Debug) {
            std.log.warn("advice: Ignoring buffer size range - non-integer value ({d} - {d})", .{ buffer_size_range.mMinimum, buffer_size_range.mMaximum });
        }
        return null;
    }

    return advice.Device.AvailableConfigs{
        .channel_count = channel_count,
        .formats = formats,
        .buffer_size = .{
            @intFromFloat(buffer_size_range.mMinimum),
            @intFromFloat(buffer_size_range.mMaximum),
        },
        .sample_rates = try sample_rates.toOwnedSlice(allocator),
        .chanenl_format = .interleaved,
    };
}

/// Gets the current sample rate of the device.
pub fn getCurrentSampleRate(self: Self) advice.Error!f64 {
    const property_adress = sys.AudioObjectPropertyAddress{
        .mSelector = sys.kAudioDevicePropertyNominalSampleRate,
        .mScope = sys.kAudioObjectPropertyScopeGlobal,
        .mElement = sys.kAudioObjectPropertyElementMaster,
    };

    var data_size: sys.UInt32 = @sizeOf(f64);
    var sample_rate: f64 = undefined;
    if (sys.AudioObjectGetPropertyData(
        self.raw,
        &property_adress,
        0,
        null,
        &data_size,
        &sample_rate,
    ) != sys.kAudioHardwareNoError) {
        return error.OsError;
    }

    return sample_rate;
}

/// Sets the sample rate of the device, if needed.
pub fn setCurrentSampleRate(self: Self, sample_rate: f64) advice.Error!void {
    if (try self.getCurrentSampleRate() == sample_rate) {
        return;
    }

    @compileError("not implemented");
}

/// Returns the available output configuration of the device.
pub fn getAvailableOutputConfigs(
    self: Self,
    allocator: std.mem.Allocator,
) advice.Error!?advice.Device.AvailableConfigs {
    return self.getAvailableConfigs(allocator, .output);
}

/// Returns the available input configuration of the device.
pub fn getAvailableInputConfigs(
    self: Self,
    allocator: std.mem.Allocator,
) advice.Error!?advice.Device.AvailableConfigs {
    return self.getAvailableConfigs(allocator, .input);
}
