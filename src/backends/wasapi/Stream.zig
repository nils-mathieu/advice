const advice = @import("advice");
const std = @import("std");
const DeviceHandle = @import("DeviceHandle.zig");
const util = @import("utility.zig");
const sys = @import("sys.zig");

const Self = @This();

/// The shared state.
shared: *Shared,
/// The spawned high-priority thread.
stream_thread: std.Thread,

/// The state shared between the stream and the stream thread.
const Shared = struct {
    /// Whether the stream should be playing or not.
    flags: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

    /// The event to signal when a command becomes available.
    events: extern struct {
        /// The event to signal when the audio client event is signaled.
        audio_client: sys.HANDLE,
        /// The event to signal when a command is available.
        command_available: sys.HANDLE,

        /// Returns a slice over the handles of this struct.
        pub inline fn asSlice(self: *const @This()) []const sys.HANDLE {
            return @as([*]const sys.HANDLE, @ptrCast(self))[0..2];
        }
    },

    pub const should_close_bit: u8 = 1 << 0;
    pub const should_play_bit: u8 = 1 << 1;
};

/// See `advice.Stream.openOutput`.
pub fn openOutput(
    device: *const advice.Device,
    allocator: std.mem.Allocator,
    config: advice.Stream.Config,
) advice.Error!Self {
    const dev: *const DeviceHandle = &device.data.device;
    const available_config = device.output_configs.?;
    const waveformat = util.makeWaveFormat(config.format, config.sample_rate, available_config.channel_count) orelse return error.UnsupportedConfig;

    var buffer_size: u32 = 2048;
    if (config.buffer_size) |bs| {
        buffer_size = bs;
    } else if (available_config.buffer_size) |bs| {
        buffer_size = std.math.clamp(buffer_size, bs[0], bs[1]);
    }

    try util.checkResult(dev.audio_client.Initialize(
        sys.AUDCLNT_SHAREMODE_SHARED,
        sys.AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        std.math.cast(i64, (@as(u64, buffer_size) * (std.time.ns_per_s / 100)) / @as(u64, config.sample_rate)) orelse return error.UnsupportedConfig,
        0,
        &waveformat,
        null,
    ));

    const audio_client_event = sys.CreateEventW(null, 0, 0, null);
    if (audio_client_event == null) {
        if (util.should_log_errors) std.log.err("advice: Failed to create event", .{});
        return error.OsError;
    }
    errdefer _ = sys.CloseHandle(audio_client_event);
    try util.checkResult(dev.audio_client.SetEventHandle(audio_client_event));

    const command_available_event = sys.CreateEventW(null, 0, 0, null);
    if (command_available_event == null) {
        if (util.should_log_errors) std.log.err("advice: Failed to create event", .{});
        return error.OsError;
    }
    errdefer _ = sys.CloseHandle(command_available_event);

    const shared = try allocator.create(Shared);
    errdefer allocator.destroy(shared);

    shared.* = Shared{
        .events = .{
            .audio_client = audio_client_event.?,
            .command_available = command_available_event.?,
        },
    };

    var stream_thread_state = try StreamThread.createOutput(.{
        .device = dev,
        .shared = shared,
        .user_state = config.state,
        .errorCallback = config.errorCallback,
        .dataCallback = config.dataCallback,
    });

    const stream_thread = std.Thread.spawn(
        .{ .allocator = allocator },
        StreamThread.runOutput,
        .{stream_thread_state},
    ) catch |err| {
        stream_thread_state.deinit();
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.OsError,
        }
    };

    return Self{
        .shared = shared,
        .stream_thread = stream_thread,
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
    // Wait for the high-priority thread to close.
    _ = self.shared.flags.fetchOr(Shared.should_close_bit, .seq_cst);
    _ = sys.SetEvent(self.shared.events.audio_client);
    self.stream_thread.join();

    // Free the stuff.
    _ = sys.CloseHandle(self.shared.events.audio_client);
    _ = sys.CloseHandle(self.shared.events.command_available);
    allocator.destroy(self.shared);

    // Clear the state in debug builds.
    self.* = undefined;
}

/// See `advice.Stream.play`.
pub fn play(self: *Self) advice.Error!void {
    _ = self.shared.flags.fetchOr(Shared.should_play_bit, .seq_cst);
    _ = sys.SetEvent(self.shared.events.command_available);
}

/// See `advice.self.pause`.
pub fn pause(self: *Self) advice.Error!void {
    _ = self.shared.flags.fetchAnd(~Shared.should_play_bit, .seq_cst);
    _ = sys.SetEvent(self.shared.events.command_available);
}

/// The state that is passed to the output stream thread.
const StreamThread = struct {
    /// The device handle being used.
    device: *const DeviceHandle,
    /// The render client for the device.
    stream_client: union {
        /// For output streams, the render client.
        render: *sys.IAudioRenderClient,
        /// The input streams, the capture client.
        capture: *sys.IAudioCaptureClient,
    },

    /// The user-defined state.
    user_state: *anyopaque,
    /// The error callback.
    errorCallback: advice.Stream.Config.ErrorCallback,
    /// The data callback.
    dataCallback: advice.Stream.Config.DataCallback,

    /// The maximum possible size of the audio buffer.
    max_buffer_size: u32,

    /// Whether the stream is currently playing or not.
    is_playing: bool,

    /// The shared state.
    shared: *Shared,

    /// The input of `createOutput`.
    pub const OutputOptions = struct {
        device: *const DeviceHandle,
        shared: *Shared,
        user_state: *anyopaque,
        errorCallback: advice.Stream.Config.ErrorCallback,
        dataCallback: advice.Stream.Config.DataCallback,
    };

    /// Creates a new output stream thread.
    fn createOutput(opts: OutputOptions) advice.Error!StreamThread {
        var render_client: *sys.IAudioRenderClient = undefined;
        try util.checkResult(opts.device.audio_client.GetService(sys.IID_IAudioRenderClient, @ptrCast(&render_client)));
        errdefer _ = render_client.IUnknown.Release();

        return StreamThread{
            .device = opts.device,
            .is_playing = try opts.device.getCurrentPadding() > 0,
            .shared = opts.shared,
            .stream_client = .{ .render = render_client },
            .user_state = opts.user_state,
            .errorCallback = opts.errorCallback,
            .dataCallback = opts.dataCallback,
            .max_buffer_size = try opts.device.getBufferSize(),
        };
    }

    /// Frees the resources used by the output stream thread.
    fn deinit(self: *StreamThread) void {
        _ = self;
    }

    /// Runs the output stream thread.
    fn runOutput(self_const: StreamThread) void {
        var self = self_const;

        const max_error_count = 8;
        var error_count: usize = 0;

        while (true) {
            setHighPriority() catch {};
            if (self.runOutputThreadIteration()) |should_continue| {
                if (!should_continue) break;
                error_count = 0;
            } else |err| {
                if (util.should_log_errors) std.log.err("advice: Output thread iteration failed: {s}", .{@errorName(err)});
                self.errorCallback(self.user_state, err);
                error_count += 1;
                if (error_count >= max_error_count) break;
            }
        }
    }

    fn runInput(self_const: StreamThread) void {
        var self = self_const;

        const max_error_count = 8;
        var error_count: usize = 0;

        while (true) {
            setHighPriority() catch {};
            if (self.runInputThreadIteration()) |should_continue| {
                if (!should_continue) break;
                error_count = 0;
            } else |err| {
                if (util.should_log_errors) std.log.err("advice: Input thread iteration failed: {s}", .{@errorName(err)});
                self.errorCallback(self.user_state, err);
                error_count += 1;
                if (error_count >= max_error_count) break;
            }
        }
    }

    /// Sets the current thread's priority to the highest possible.
    fn setHighPriority() advice.Error!void {
        const thread_id = sys.GetCurrentThreadId();
        _ = sys.SetThreadPriority(@ptrFromInt(thread_id), sys.THREAD_PRIORITY_TIME_CRITICAL);
    }

    /// Runs one output thread iteration.
    ///
    /// Returns whether the thread should continue running.
    fn runOutputThreadIteration(self: *StreamThread) advice.Error!bool {
        if (!try self.processCommand()) return false;
        try self.processOutput();
        try self.blockForThreadEvent();
        return true;
    }

    /// Runs one input thread iteration.
    ///
    /// Returns whether the thread should continue running.
    fn runInputThreadIteration(self: *StreamThread) advice.Error!bool {
        if (!try self.processCommand()) return false;
        try self.processInput();
        try self.blockForThreadEvent();
        return true;
    }

    /// Process the commands available to the stream thread.
    ///
    /// Returns whether the thread should continue running.
    fn processCommand(self: *StreamThread) advice.Error!bool {
        const flags = self.shared.flags.load(.seq_cst);
        const should_play = flags & Shared.should_play_bit != 0;
        const should_close = flags & Shared.should_close_bit != 0;

        if (should_close) return false;

        if (self.is_playing != should_play) {
            self.is_playing = should_play;

            if (self.is_playing) {
                try util.checkResult(self.device.audio_client.Start());
            } else {
                try util.checkResult(self.device.audio_client.Stop());
            }
        }

        return true;
    }

    /// Blocks the current thread until an event is signaled.
    fn blockForThreadEvent(self: *StreamThread) advice.Error!void {
        const events = self.shared.events.asSlice();

        const ret = sys.WaitForMultipleObjectsEx(
            @intCast(events.len),
            events.ptr,
            0,
            std.math.maxInt(u32),
            0,
        );

        if (ret == @intFromEnum(sys.WAIT_FAILED)) {
            if (util.should_log_errors) std.log.err("advice: Failed to wait for thread event: {d}", .{ret});
            return error.OsError;
        }
    }

    /// Processes a stream buffer for output.
    fn processOutput(self: *StreamThread) advice.Error!void {
        const frames_available = self.max_buffer_size - try self.device.getCurrentPadding();
        if (frames_available == 0) return;

        var buffer: [*]u8 = undefined;
        try util.checkResult(self.stream_client.render.GetBuffer(frames_available, @ptrCast(&buffer)));

        self.dataCallback(
            self.user_state,
            buffer,
            frames_available,
            0,
            0,
        );

        try util.checkResult(self.stream_client.render.ReleaseBuffer(frames_available, 0));
    }

    /// Processes a stream buffer for input.
    fn processInput(self: *StreamThread) advice.Error!void {
        _ = self;
        @compileError("not implemented");
    }
};
