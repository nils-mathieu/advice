//! Contains information about all the possible device configurations available to a specific
//! device.

const std = @import("std");
const advice = @import("advice");

const Self = @This();

/// The number of available channels.
channel_count: u32,

/// The list of available sampling rates for the device.
///
/// This is a number of audio *frames*.
sample_rates: []u32,

/// The range of valid sizes for the buffer used by the device.
///
/// If `none`, the buffer size is either unknown or any size is valid.
buffer_size: ?[2]u32,

/// The list of available formats for the device.
formats: Formats,

/// The channel format used by the device.
chanenl_format: ChannelFormat,

/// The list of available formats for a device.
pub const Formats = packed struct {
    /// Whether the device supports 32-bit floating point samples.
    f32: bool = false,
    /// Whether the device supports 64-bit floating point samples.
    f64: bool = false,
    /// Whether the device supports 8-bit unsinged samples.
    u8: bool = false,
    /// Whether the device supports 16-bit unsigned samples.
    u16: bool = false,
    /// Whether the device supports 24-bit unsigned samples.
    u24: bool = false,
    /// Whether the device supports 32-bit unsigned samples.
    u32: bool = false,
    /// Whether the device supports 64-bit unsigned samples.
    u64: bool = false,
    /// Whether the device supports 8-bit signed samples.
    i8: bool = false,
    /// Whether the device supports 16-bit signed samples.
    i16: bool = false,
    /// Whether the device supports 24-bit signed samples.
    i24: bool = false,
    /// Whether the device supports 32-bit signed samples.
    i32: bool = false,
    /// Whether the device supports 64-bit signed samples.
    i64: bool = false,

    pub fn format(self: Formats, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);

        if (self.f32) try writer.writeAll("f32, ");
        if (self.f64) try writer.writeAll("f64, ");
        if (self.u8) try writer.writeAll("u8, ");
        if (self.u16) try writer.writeAll("u16, ");
        if (self.u24) try writer.writeAll("u24, ");
        if (self.u32) try writer.writeAll("u32, ");
        if (self.u64) try writer.writeAll("u64, ");
        if (self.i8) try writer.writeAll("i8, ");
        if (self.i16) try writer.writeAll("i16, ");
        if (self.i24) try writer.writeAll("i24, ");
        if (self.i32) try writer.writeAll("i32, ");
        if (self.i64) try writer.writeAll("i64, ");
    }

    /// Returns whether this `Format` instance contains any of the formats that are in the other
    /// `Format` instance.
    pub fn supports(self: Formats, other: advice.Stream.Format) bool {
        switch (other) {
            .f32 => return self.f32,
            .f64 => return self.f64,
            .u8 => return self.u8,
            .u16 => return self.u16,
            .u24 => return self.u24,
            .u32 => return self.u32,
            .u64 => return self.u64,
            .i8 => return self.i8,
            .i16 => return self.i16,
            .i24 => return self.i24,
            .i32 => return self.i32,
            .i64 => return self.i64,
        }
    }

    /// Returns whether this `Format` instance is empty.
    pub fn isEmpty(self: Formats) bool {
        const i: u12 = @bitCast(self);
        return i == 0;
    }

    /// Returns any of the formats that are supported by this `Format` instance.
    ///
    /// Assumes at least one format is supported.
    pub fn any(self: Formats) advice.Stream.Format {
        if (self.f32) return .f32;
        if (self.i24) return .i24;
        if (self.u24) return .u24;
        if (self.i16) return .i16;
        if (self.u16) return .u16;
        if (self.f64) return .f64;
        if (self.i32) return .i32;
        if (self.u32) return .u32;
        if (self.i64) return .i64;
        if (self.u64) return .u64;
        if (self.u8) return .u8;
        if (self.i8) return .i8;
        unreachable;
    }
};

/// Describes how channels are formatted.
pub const ChannelFormat = enum {
    /// Channels are interleaved.
    ///
    /// This means that the samples for each channel are stored in a single array. Each component
    /// of frame of audio are stored contiguously in memory and the samples for each channel are
    /// interleaved.
    ///
    /// For example, if there are two channels, the samples for each channel are stored like this:
    ///
    /// ```text
    /// [L, R, L, R, L, R, ...]
    /// ```
    interleaved,

    /// Channels are non-interleaved.
    ///
    /// This means that the samples for each channel are stored in separate arrays. Each component
    /// of a frame of audio are stored in separate arrays.
    ///
    /// For example, if there are two channels, the samples for each channel are stored like this:
    ///
    /// ```text
    /// [L, L, L, ...]
    /// [R, R, R, ...]
    /// ```
    non_interleaved,
};

/// Frees the resources associated with the available device configurations.
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.sample_rates);
    self.sample_rates = undefined;
}

/// Returns whether the device supports the given format.
pub fn supportsFormat(self: Self, fmt: advice.Device.Format) bool {
    return self.formats.supports(fmt);
}

/// Returns whether the device supports the given buffer size.
pub fn supportsBufferSize(self: Self, size: u32) bool {
    if (self.buffer_size) |bs| {
        return size >= bs[0] and size <= bs[1];
    } else {
        return true;
    }
}

/// Returns whether the device supports the given sample rate.
pub fn supportsSampleRate(self: Self, rate: u32) bool {
    return std.mem.indexOfScalar(u32, self.sample_rates, rate) != null;
}

/// Returns the format the stream should use, given a list of preferred formats.
///
/// If none of the formats are supported, any of the preferred formats will be returned.
pub fn getPreferredFormat(self: Self, preferred_formats: []const advice.Stream.Format) advice.Stream.Format {
    for (preferred_formats) |format| if (self.formats.supports(format)) return format;
    return self.formats.any();
}

/// Returns the unsigned distance between two unsigned integers.
inline fn unsignedDistance(a: u32, b: u32) u32 {
    return @as(u32, @abs(@as(i32, @bitCast(a -% b))));
}

/// Returns the sample rate supported by the device that is closest to the provided
/// preferred sample rate.
pub fn getPreferredSampleRate(self: Self, preferred_sample_rate: u32) u32 {
    var closest: u32 = 0;
    var closest_diff: u32 = std.math.maxInt(u32);

    for (self.sample_rates) |sr| {
        const diff = unsignedDistance(sr, preferred_sample_rate);
        if (diff < closest_diff) {
            closest = sr;
            closest_diff = diff;
        }
    }

    return closest;
}

/// Returns the buffer size supported by the device that is closest to the provided
pub fn getPreferredBufferSize(self: Self, preferred_buffer_size: u32) ?u32 {
    if (self.buffer_size) |bs| {
        return std.math.clamp(preferred_buffer_size, bs[0], bs[1]);
    } else {
        return null;
    }
}
