const std = @import("std");
const advice = @import("advice");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var host = try advice.Host.default(a);
    defer host.deinit(a);

    printHostInfo(&host);
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
    } else {
        std.debug.print("No default output device\n", .{});
    }
    if (host.default_input_device) |dev| {
        std.debug.print("Default input device: {s}\n", .{dev.name});
    } else {
        std.debug.print("No default input device\n", .{});
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
