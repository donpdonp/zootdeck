// toot_list.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const toot = @import("./toot.zig");

pub const TootList = std.LinkedList(toot.TootType);

// pub fn TootList(comptime T: type) type {
//   return struct {
//     const Self = @This();

//     list: std.LinkedList(T),
//     first: ?T,

//     pub fn init() Self {
//       return Self{
//           .first = null,
//       };
//     }
//   };
// }