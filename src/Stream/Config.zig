const advice = @import("advice");

/// The signature of the function responsible for writing/reading data to/from the stream.
/// A pointer to the buffer that should be filled with audio data. It is initially filled with
/// possibly uninitialized data. The exact datatype referenced by this pointer depends on the
/// `format` specified int the stream configuration.
///
/// By the time the callback returns, the buffer must be filled with `frame_count` frames of
/// audio data.
///
/// # Parameters
///
/// - `state`: The pointer to the state that was passed to the stream configuration. Used
///   to reference custom data from within the stream's callbacks.
///
/// - `data`: The pointer to the buffer that should be filled (or read from) with audio
///   data.
///
/// - `frame_count`: The number of frames that should be written to the buffer. This does
///   *not* take the format size or channel count into account. In other words, the total
///   number of referenced bytes is `frame_count * channel_count * @sizeOf(format)`.
///
/// - `current_timestamp`: The timestamp, in nanoseconds. The epoch is undefined, meaning that this
///   timetamp may only be used to calculate time between two existing timestamps.
///
/// - `effective_timestamp`: A timestamp, in nanoseconds. For output streams, this is the
///   time at which the data is expected to be played. For input streams, this is the time
///   at which the data was recorded. If the audio backend does not provide this information
///   (or it is not available right now), this value will be `0`.
pub const DataCallback = *const fn (
    state: *anyopaque,
    data: *anyopaque,
    frame_count: usize,
    current_timestamp: u64,
    effective_timestamp: u64,
) void;

/// The signature of the function responsible for handling errors that occur during the
/// stream's lifetime.
pub const ErrorCallback = *const fn (state: *anyopaque, err: advice.Error) void;

/// The format that the stream should use.
///
/// The format must be part of the supported formats of the device's input/output
/// configurations.
format: advice.Stream.Format,

/// The sample rate that the stream should use.
///
/// The sample rate must be part of the supported sample rates of the device's input/output
/// configurations.
sample_rate: u32,

/// The preffered buffer size that the stream should use.
///
/// If `null`, the device will choose a suitable buffer size by itself. Note that this
/// sometimes results in large buffer sizes, so it is recommended to specify a buffer size
/// if you need low latency.
///
/// **Remarks:** This is mostly a hint for the device and may not be respected.
buffer_size: ?u32,

/// A state pointer that will be passed to the callbacks.
state: *anyopaque,

/// A callback that will be called when more data must be written/read from the stream.
dataCallback: DataCallback,

/// A callback that will be called when errors occur during the stream's lifetime.
errorCallback: ErrorCallback,
