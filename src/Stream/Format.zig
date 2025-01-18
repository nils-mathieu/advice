const std = @import("std");

/// A potential stream format.
pub const Format = enum {
    /// The 32-bit floating point format.
    f32,
    /// The 64-bit floating point format.
    f64,
    /// The 8-bit unsigned integer format.
    u8,
    /// The 16-bit unsigned integer format.
    u16,
    /// The 24-bit unsigned integer format.
    u24,
    /// The 32-bit unsigned integer format.
    u32,
    /// The 64-bit unsigned integer format.
    u64,
    /// The 8-bit signed integer format.
    i8,
    /// The 16-bit signed integer format.
    i16,
    /// The 24-bit signed integer format.
    i24,
    /// The 32-bit signed integer format.
    i32,
    /// The 64-bit signed integer format.
    i64,

    /// Returns the size of a sample encoded in this format, in bytes.
    pub fn sizeInBytes(self: Format) u32 {
        switch (self) {
            .f32 => return 4,
            .f64 => return 8,
            .u8 => return 1,
            .u16 => return 2,
            .u24 => return 3,
            .u32 => return 4,
            .u64 => return 8,
            .i8 => return 1,
            .i16 => return 2,
            .i24 => return 3,
            .i32 => return 4,
            .i64 => return 8,
        }
    }

    /// Returns whether this format is a floating point format.
    pub fn isFloat(self: Format) bool {
        switch (self) {
            .f32, .f64 => return true,
            else => return false,
        }
    }

    pub fn format(
        self: Format,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);

        switch (self) {
            .f32 => try writer.print("f32", .{}),
            .f64 => try writer.print("f64", .{}),
            .u8 => try writer.print("u8", .{}),
            .u16 => try writer.print("u16", .{}),
            .u24 => try writer.print("u24", .{}),
            .u32 => try writer.print("u32", .{}),
            .u64 => try writer.print("u64", .{}),
            .i8 => try writer.print("i8", .{}),
            .i16 => try writer.print("i16", .{}),
            .i24 => try writer.print("i24", .{}),
            .i32 => try writer.print("i32", .{}),
            .i64 => try writer.print("i64", .{}),
        }
    }
};
