const sys = @import("sys.zig");
const std = @import("std");
const builtin = @import("builtin");
const advice = @import("advice");

/// Extracts the content of a `CFStringRef` as a byte slice encoded as UTF-8 data.
///
/// The returned must be freed by the caller.
pub fn extractCFString(s: sys.CFStringRef, allocator: std.mem.Allocator) advice.Error![]u8 {
    // If the string is already encoded in UTF-8, there is no conversion needed. In that case,
    // we can just dupe the pointer to make sure we're the one owning the memory.
    const utf8_ptr = sys.CFStringGetCStringPtr(s, sys.kCFStringEncodingUTF8);
    if (utf8_ptr != null) return allocator.dupe(u8, std.mem.span(utf8_ptr));

    // Otherwise, we need to perform a conversion.

    // 1. Compute the maximum length that the UTF-8 string might have.
    const utf16_len = sys.CFStringGetLength(s);
    const max_len_long = sys.CFStringGetMaximumSizeForEncoding(
        utf16_len,
        sys.kCFStringEncodingUTF8,
    );
    const max_len = std.math.cast(usize, max_len_long) orelse return error.OsError;

    // 2. Read the string into the allocated buffer.
    var buf = try std.ArrayListUnmanaged(u8).initCapacity(allocator, max_len);
    if (sys.CFStringGetCString(
        s,
        buf.allocatedSlice().ptr,
        max_len_long,
        sys.kCFStringEncodingUTF8,
    ) == 0) {
        return error.OsError;
    }

    return buf.toOwnedSlice(allocator);
}

/// Returns the timebase information of the system.
pub fn getTimebaseInfo() error{OsError}!sys.struct_mach_timebase_info {
    var info: sys.struct_mach_timebase_info = undefined;
    if (sys.mach_timebase_info(&info) != sys.KERN_SUCCESS) {
        return error.OsError;
    }
    return info;
}

/// Returns whether the given value is an integer.
pub inline fn isInteger(value: f64) bool {
    return value == @trunc(value);
}
