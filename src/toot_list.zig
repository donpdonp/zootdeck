// toot_list.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const toot = @import("./toot.zig");

pub const TootList = std.LinkedList(toot.TootType);
