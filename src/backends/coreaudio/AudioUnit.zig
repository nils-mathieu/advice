const sys = @import("sys.zig");
const advice = @import("advice");
const builtin = @import("builtin");
const std = @import("std");

const Self = @This();

/// The inner AudioUnit object.
obj: sys.AudioUnit,

/// A possible element of the audio unit.
pub const Element = enum(sys.AudioUnitElement) {
    output = 0,
    input = 1,
};

/// A possible scope of the audio unit.
pub const Scope = enum(sys.AudioUnitScope) {
    global = sys.kAudioUnitScope_Global,
    input = sys.kAudioUnitScope_Input,
    output = sys.kAudioUnitScope_Output,
};

/// The configuration for an audio unit.
pub const Config = struct {
    /// Whether the audio unit is an output unit.
    ///
    /// Otherwise it's an input unit.
    is_output: bool,
    /// Whether the audio unit is the default unit for its type (input/output).
    is_default: bool,
};

/// Creates a new audio unit.
///
/// The created object must be destroyed by the caller.
pub fn init(config: Config) advice.Error!Self {
    const sub_type = if (config.is_default and config.is_output)
        sys.kAudioUnitSubType_DefaultOutput
    else
        sys.kAudioUnitSubType_HALOutput;

    const desc = sys.AudioComponentDescription{
        .componentType = sys.kAudioUnitType_Output,
        .componentSubType = @bitCast(sub_type),
        .componentManufacturer = sys.kAudioUnitManufacturer_Apple,
    };

    const component = sys.AudioComponentFindNext(null, &desc);
    if (component == null) return error.OsError;

    var audio_unit: sys.AudioUnit = null;
    if (sys.AudioComponentInstanceNew(
        component,
        &audio_unit,
    ) != sys.noErr) {
        return error.OsError;
    }

    return Self{ .obj = audio_unit };
}

/// Destroys the audio unit.
pub fn deinit(self: *Self) void {
    if (sys.AudioUnitUninitialize(self.obj) != sys.noErr and builtin.mode == .Debug) {
        std.log.warn("advice: Failed to uninitialize audio unit", .{});
    }
    if (sys.AudioComponentInstanceDispose(self.obj) != sys.noErr and builtin.mode == .Debug) {
        std.log.warn("advice: Failed to dispose of audio unit", .{});
    }
}

/// Initializes the audio unit.
pub fn initialize(self: *Self) advice.Error!void {
    if (sys.AudioUnitInitialize(self.obj) != sys.noErr) {
        return error.OsError;
    }
}

/// Sets the current device of the audio unit.
pub fn setCurrentDevice(self: *Self, device: sys.AudioDeviceID, element: Element) advice.Error!void {
    if (sys.AudioUnitSetProperty(
        self.obj,
        sys.kAudioOutputUnitProperty_CurrentDevice,
        sys.kAudioUnitScope_Global,
        @intFromEnum(element),
        &device,
        @sizeOf(sys.AudioDeviceID),
    ) != sys.noErr) {
        return error.OsError;
    }
}

/// The basic description of an audio stream.
const BasicDescription = struct {
    /// The number of channels.
    channels: u32,
    /// The sample rate.
    sample_rate: u32,
    /// The format of the audio stream.
    format: advice.Stream.Format,
};

/// Configures an audio stream basic description.
///
/// This sets the `AudioStreamBasicDescription` of the audio unit.
pub fn setBasicDescription(self: *Self, scope: Scope, element: Element, desc: BasicDescription) advice.Error!void {
    var flags: sys.AudioFormatFlags = sys.kAudioFormatFlagIsPacked;
    if (desc.format.isFloat()) flags |= sys.kAudioFormatFlagIsFloat;

    const data = sys.AudioStreamBasicDescription{
        .mBitsPerChannel = desc.format.sizeInBytes() * 8,
        .mBytesPerFrame = desc.format.sizeInBytes() * desc.channels,
        .mChannelsPerFrame = desc.channels,
        .mFramesPerPacket = 1,
        .mBytesPerPacket = desc.format.sizeInBytes() * desc.channels,
        .mFormatID = sys.kAudioFormatLinearPCM,
        .mSampleRate = @floatFromInt(desc.sample_rate),
        .mFormatFlags = flags,
    };
    const status = sys.AudioUnitSetProperty(
        self.obj,
        sys.kAudioUnitProperty_StreamFormat,
        @intFromEnum(scope),
        @intFromEnum(element),
        &data,
        @sizeOf(sys.AudioStreamBasicDescription),
    );
    switch (status) {
        sys.noErr => {},
        sys.kAudioFormatUnsupportedDataFormatError => return error.UnsupportedConfig,
        else => {
            if (builtin.mode == .Debug)
                std.log.warn("advice: Failed to set basic description: {d}", .{status});
            return error.OsError;
        },
    }
}

/// Sets the buffer size.
pub fn setBufferSize(self: *Self, scope: Scope, element: Element, buffer_size: u32) advice.Error!void {
    if (sys.AudioUnitSetProperty(
        self.obj,
        sys.kAudioDevicePropertyBufferFrameSize,
        @intFromEnum(scope),
        @intFromEnum(element),
        &buffer_size,
        @sizeOf(u32),
    ) != sys.noErr) {
        return error.OsError;
    }
}

/// Sets the render callback for the audio unit.
pub fn setRenderCallback(
    self: *Self,
    scope: Scope,
    element: Element,
    state: ?*anyopaque,
    callback: sys.AURenderCallback,
) advice.Error!void {
    const info = sys.AURenderCallbackStruct{
        .inputProc = callback,
        .inputProcRefCon = state,
    };

    if (sys.AudioUnitSetProperty(
        self.obj,
        sys.kAudioUnitProperty_SetRenderCallback,
        @intFromEnum(scope),
        @intFromEnum(element),
        &info,
        @sizeOf(sys.AURenderCallbackStruct),
    ) != sys.noErr) {
        return error.OsError;
    }
}

/// Starts the audio unit.
pub fn start(self: *Self) advice.Error!void {
    const status = sys.AudioOutputUnitStart(self.obj);
    if (status != sys.noErr) {
        if (builtin.mode == .Debug)
            std.log.warn("advice: Failed to start audio unit: {d}", .{status});
        return error.OsError;
    }
}

/// Stops the audio unit.
pub fn stop(self: *Self) advice.Error!void {
    const status = sys.AudioOutputUnitStop(self.obj);
    if (status != sys.noErr) {
        if (builtin.mode == .Debug)
            std.log.warn("advice: Failed to stop audio unit: {d}", .{status});
        return error.OsError;
    }
}
