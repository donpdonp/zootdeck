const std = @import("std");
const util = @import("util.zig");
const lmdb = @import("db/lmdb.zig");

test "modules" {
    _ = lmdb;
    // std.testing.refAllDecls(@This);
}
