//! A stream on the CoreAudio platform.

const advice = @import("advice");
const std = @import("std");
const AudioUnit = @import("AudioUnit.zig");
const sys = @import("sys.zig");
const util = @import("utility.zig");

const Self = @This();

/// The audio unit object.
audio_unit: AudioUnit,
/// The state of the stream.
render_callback_state: ?*RenderCallbackState = null,

/// The render callback state.
const RenderCallbackState = struct {
    user_data: *anyopaque,
    userCallback: advice.Stream.Config.DataCallback,
    frame_size: usize,
    timebase_info_numerator: u64,
    timebase_info_denominator: u64,

    /// Creates a new render callback state.
    pub fn init(
        user_data: *anyopaque,
        user_callback: advice.Stream.Config.DataCallback,
        frame_size: usize,
    ) advice.Error!RenderCallbackState {
        const timebase = try util.getTimebaseInfo();
        return RenderCallbackState{
            .user_data = user_data,
            .userCallback = user_callback,
            .frame_size = frame_size,
            .timebase_info_denominator = timebase.denom,
            .timebase_info_numerator = timebase.numer,
        };
    }

    fn renderCallback(
        self: *@This(),
        timestamp: *const sys.AudioTimeStamp,
        buffers: []sys.AudioBuffer,
    ) void {
        const buffer = buffers[0];

        self.userCallback(
            self.user_data,
            buffer.mData.?,
            buffer.mDataByteSize / self.frame_size,
            (timestamp.mHostTime * self.timebase_info_numerator) / self.timebase_info_denominator,
            0,
        );
    }

    /// The render callback that will be passed to the CoreAudio API.
    pub fn rawRenderCallback(
        state_arg: ?*anyopaque,
        _: [*c]sys.AudioUnitRenderActionFlags, // flags
        timestamp: [*c]const sys.AudioTimeStamp,
        _: sys.UInt32, // bus_number
        _: sys.UInt32, // frame_count
        buffer_list: [*c]sys.AudioBufferList,
    ) callconv(.c) sys.OSStatus {
        @This().renderCallback(
            @alignCast(@ptrCast(state_arg)),
            @ptrCast(timestamp),
            @as([*]sys.AudioBuffer, &buffer_list.*.mBuffers)[0..buffer_list.*.mNumberBuffers],
        );
        return sys.noErr;
    }
};

/// See `advice.Stream.openOutput`.
pub fn openOutput(
    device: *const advice.Device,
    allocator: std.mem.Allocator,
    config: advice.Stream.Config,
) advice.Error!Self {
    var audio_unit = try AudioUnit.init(.{
        .is_output = true,
        .is_default = device.data.flags.default_output,
    });
    errdefer audio_unit.deinit();

    const scope = AudioUnit.Scope.input;
    const element = AudioUnit.Element.output;

    try audio_unit.setCurrentDevice(device.data.id.raw, element);

    try audio_unit.setBasicDescription(
        scope,
        element,
        .{
            .channels = device.output_configs.?.channel_count,
            .sample_rate = config.sample_rate,
            .format = config.format,
        },
    );

    if (config.buffer_size) |buffer_size| {
        try audio_unit.setBufferSize(scope, element, buffer_size);
    }

    const render_callback_state = try allocator.create(RenderCallbackState);
    render_callback_state.* = try RenderCallbackState.init(
        config.state,
        config.dataCallback,
        config.format.sizeInBytes() * device.output_configs.?.channel_count,
    );
    errdefer allocator.destroy(render_callback_state);

    try audio_unit.setRenderCallback(
        scope,
        element,
        render_callback_state,
        RenderCallbackState.rawRenderCallback,
    );

    try audio_unit.initialize();

    return Self{
        .audio_unit = audio_unit,
        .render_callback_state = render_callback_state,
    };
}

/// See `advice.Stream.openInput`.
pub fn openInput(
    device: *const advice.Device,
    allocator: std.mem.Allocator,
    config: advice.Stream.Config,
) advice.Error!Self {
    _ = device;
    _ = allocator;
    _ = config;
    @compileError("not implemented");
}

/// See `advice.Stream.close`.
pub fn close(self: *Self, allocator: std.mem.Allocator) void {
    self.audio_unit.deinit();
    if (self.render_callback_state) |a| allocator.destroy(a);
    self.* = undefined;
}

/// See `advice.Stream.start`.
pub fn play(self: *Self) advice.Error!void {
    try self.audio_unit.start();
}

/// See `advice.Stream.pause`.
pub fn pause(self: *Self) advice.Error!void {
    try self.audio_unit.stop();
}
