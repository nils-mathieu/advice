//! Advice (Audio DeVICE) is a thin platform-agnostic audio playback and recording library
//! for Zig.
//!
//! It provides the minimal set of features needed to play and record audio in a fairly
//! platform-independent way. It is meant to provide the least overhead possible.

const builtin = @import("builtin");

/// The platform-specific implementation of the library.
///
/// It is discouraged to use this directly, as everything within it is platform-specific and must
/// be gated behind the appropriate checks.
pub const backend = switch (builtin.os.tag) {
    .macos, .ios => @import("backends/coreaudio/root.zig"),
    .windows => @import("backends/wasapi/root.zig"),
    else => unreachable,
};

/// The error type for the library.
pub const Error = error{
    /// The operating system returned an unexpected error that cannot be handled.
    OsError,
    /// The system ran out of memory.
    OutOfMemory,
    /// Returned when the requested configuration is not supported by the device.
    UnsupportedConfig,
};

pub const Host = @import("Host.zig");
pub const Device = @import("Device/Device.zig");
pub const Stream = @import("Stream/Stream.zig");
