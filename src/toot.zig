// toot.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

pub const TootType = std.hash_map.HashMap([]const u8,
                                          std.json.Value,
                                          std.mem.hash_slice_u8,
                                          std.mem.eql_slice_u8);

