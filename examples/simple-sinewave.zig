const std = @import("std");
const advice = @import("advice");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var host = try advice.Host.default(a);
    defer host.deinit(a);
    printHostInfo(&host);

    const dev = host.default_output_device orelse return error.NoDeviceFound;
    const available_conf = dev.output_configs.?;

    var state = State{
        .sample_rate = @floatFromInt(host.default_output_device.?.output_configs.?.sample_rates[0]),
        .channels = available_conf.channel_count,
    };

    const config = advice.Stream.Config{
        .sample_rate = available_conf.getPreferredSampleRate(44100),
        .format = available_conf.getPreferredFormat(&.{}),
        .buffer_size = available_conf.getPreferredBufferSize(256),
        .state = &state,
        .dataCallback = dataCallback,
        .errorCallback = errorCallback,
    };

    std.debug.assert(config.format == .f32);

    std.debug.print(
        \\
        \\Choosen config:
        \\ - Name: {s}
        \\ - Sample rate: {d}
        \\ - Format: {}
        \\ - Buffer size: {d}
        \\ - Channels: {d}
        \\
    , .{
        dev.name,
        config.sample_rate,
        config.format,
        config.buffer_size orelse 0,
        available_conf.channel_count,
    });

    var stream = try advice.Stream.openOutput(dev, a, config);
    defer stream.close(a);

    std.debug.print("\nStarting...\n", .{});
    try stream.play();

    std.time.sleep(std.time.ns_per_s * 3);

    std.debug.print("Stopping...\n", .{});
    try stream.pause();
}

fn printHostInfo(host: *const advice.Host) void {
    std.debug.print("Available devices:\n", .{});
    for (host.devices) |dev| {
        std.debug.print(" - {s}\n", .{dev.name});
        if (dev.output_configs) |*c| {
            std.debug.print("    - Output config:\n", .{});
            printConfigs(c);
        }
        if (dev.input_configs) |*c| {
            std.debug.print("    - Input config:\n", .{});
            printConfigs(c);
        }
    }
    if (host.default_output_device) |dev| {
        std.debug.print("Default output device: {s}\n", .{dev.name});
    }
    if (host.default_input_device) |dev| {
        std.debug.print("Default input device: {s}\n", .{dev.name});
    }
}

fn printConfigs(c: *const advice.Device.AvailableConfigs) void {
    std.debug.print("       - Sample rates: ", .{});
    for (c.sample_rates) |rate| {
        std.debug.print("{d}, ", .{rate});
    }
    std.debug.print("\n", .{});
    if (c.buffer_size) |bs| {
        std.debug.print("       - Buffer size: {d} - {d}\n", .{ bs[0], bs[1] });
    } else {
        std.debug.print("       - Buffer size: N/A\n", .{});
    }
    std.debug.print("       - Formats: {}\n", .{c.formats});
}

const State = struct {
    phase: f64 = 0.0,
    sample_rate: f64,
    channels: u32,
};

fn dataCallback(
    state_any: *anyopaque,
    data_any: *anyopaque,
    frame_count: usize,
    _: u64,
    _: u64,
) void {
    const state: *State = @alignCast(@ptrCast(state_any));
    const data: []f32 = advice.Stream.getCallbackData(
        false,
        f32,
        .interleaved,
        data_any,
        state.channels,
        frame_count,
    );

    for (0..frame_count) |i| {
        const sample: f32 = @floatCast(0.5 * @sin(state.phase));
        state.phase += 2.0 * std.math.pi * 440.0 * (1.0 / state.sample_rate);

        for (0..state.channels) |j| {
            data[i * state.channels + j] = sample;
        }
    }
}

fn errorCallback(state: *anyopaque) void {
    _ = state;
}
