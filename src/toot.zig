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

    pub fn id(self: *const Self) []const u8 {
      if(self.hashmap.get("id")) |kv| {
        return kv.value.String;
      } else {
        unreachable;
      }
    }

    pub fn author(self: *const Self, acct: []const u8) bool {
      if(self.hashmap.get("account")) |kv| {
        if(kv.value.Object.get("acct")) |akv| {
          const existing_acct = akv.value.String;
          return std.mem.compare(u8, acct, existing_acct) == std.mem.Compare.Equal;
        } else {
          return false;
        }
      } else {
        return false;
      }
    }
  };
}
