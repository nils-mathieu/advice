const root = @import("root");

/// Whether to log errors that occur in the library. Useful for debugging.
pub const should_log_errors = if (@hasDecl(root, "__advice_log_errors")) @as(bool, root.__advice_log_errors) else false;
