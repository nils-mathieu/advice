const std = @import("std");
const sys = @import("sys.zig");

/// Whether the COM interface is initialized.
threadlocal var com_initialized = false;

/// Ensures that the COM interface is initialized.
///
/// This function must be called on every thread that uses COM.
pub fn ensureComInitialized() void {
    if (com_initialized) return; // Already initialized.

    const result = sys.CoInitializeEx(null, sys.COINIT_APARTMENTTHREADED);
    if (result != sys.RPC_E_CHANGED_MODE and result != sys.SUCCESS) {
        // Something really bad happened. It's weird that we can't initialize COM.
        std.debug.panic("advice: Failed to initialize COM: {}\n", .{result});
    }

    com_initialized = true;
}
