const sys = @import("sys.zig");
const std = @import("std");
const advice = @import("advice");

pub const should_log_errors = @import("../../utility.zig").should_log_errors;

/// Checks the result of a win32 function and logs an error if it failed.
pub fn checkResult(result: sys.HRESULT) error{OsError}!void {
    if (result != sys.SUCCESS) {
        if (should_log_errors) std.log.err("advice: WASAPI error: {}", .{result});
        return error.OsError;
    }
}

/// Constructs a `WAVEFORMATEX`.
pub fn makeWaveFormat(
    format: advice.Stream.Format,
    sample_rate: u32,
    channel_count: u32,
) ?sys.WAVEFORMATEX {
    const bits_per_sample: u16 = @intCast(format.sizeInBytes() * 8);
    const block_align = std.math.cast(u16, channel_count * format.sizeInBytes()) orelse return null;
    const bytes_per_sec = sample_rate * block_align;
    const channels: u16 = std.math.cast(u16, channel_count) orelse return null;

    return sys.WAVEFORMATEX{
        .wFormatTag = switch (format) {
            .u16, .u24, .u32, .u64, .i8 => return null,
            .u8, .i16, .i24, .i32, .i64 => sys.WAVE_FORMAT_PCM,
            .f32, .f64 => sys.WAVE_FORMAT_IEEE_FLOAT,
        },
        .nAvgBytesPerSec = bytes_per_sec,
        .nBlockAlign = block_align,
        .nChannels = channels,
        .nSamplesPerSec = sample_rate,
        .wBitsPerSample = bits_per_sample,
        .cbSize = 0,
    };
}
