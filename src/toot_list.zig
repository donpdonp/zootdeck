// toot_list.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const toot = @import("./toot.zig");
const util = @import("./util.zig");

//pub const TootList = Lists.LinkedList(toot.TootType);
pub const TootList = TootListMk(toot.TootType);

pub fn TootListMk(comptime T: type) type {
  return struct {
    const Self = @This();
    const ListType = std.TailQueue(T);
    list: ListType,

    pub fn init() Self {
      return Self{
        .list = ListType.init(),
      };
    }

    pub fn first(self: *Self) ?*ListType.Node {
      return self.list.first;
    }

    pub fn contains(self: *Self, item: T) bool {
      var ptr = self.list.first;
      while(ptr) |listItem| {
        if(util.hashIdSame(T, listItem.data, item)) {
          return true;
        }
        ptr = listItem.next;
      }
      return false;
    }

    pub fn sortedInsert(self: *Self, item: T, allocator: *Allocator) void {
      const itemDate = item.get("created_at").?.value.String;
      const node = self.list.createNode(item, allocator) catch unreachable;
      var current = self.list.first;
      while(current) |listItem| {
        const listItemDate = listItem.data.get("created_at").?.value.String;
        if(std.mem.compare(u8, itemDate, listItemDate) == std.mem.Compare.GreaterThan) {
          self.list.insertBefore(listItem, node);
          return;
        } else {
        }
        current = listItem.next;
      }
      self.list.append(node);
    }

    pub fn count(self: *Self) usize {
      var counter = usize(0);
      var current = self.list.first;
      while(current) |item| { counter = counter +1; current = item.next; }
      return counter;
    }

  };
}
