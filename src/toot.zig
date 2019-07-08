// toot.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

pub fn Toot() type {
  return struct {
    hashmap: Toothashmap = undefined,

    const Self = @This();
    const K = []const u8;
    const V = std.json.Value;
    const Toothashmap = std.hash_map.HashMap(K, V,
                                             std.mem.hash_slice_u8,
                                             std.mem.eql_slice_u8);
    pub fn init(hash: Toothashmap) Self {
      return Self{
        .hashmap = hash
      };
    }

    pub fn get(self: *const Self, key: K) ?*Toothashmap.KV {
      return self.hashmap.get(key);
    }

    pub fn author(self: *const Self, acct: []const u8) bool {
      return false;
    }
  };
}
