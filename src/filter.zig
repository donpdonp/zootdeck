// filter.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const string = []const u8;
const toot_lib = @import("toot.zig");

pub const ptree = struct {
  hostname: string,
  tags: *toot_lib.Type.TagList,

  const Self = @This();

  pub fn host(self: *const Self) []const u8 {
    return self.hostname;
  }

  pub fn match(self: *const Self, toot: *toot_lib.Type) bool {
    if(self.tags.count() == 0) {
      return true;
    } else {
      var iter = self.tags.iterator();
      while(iter.next()) |filter_tag| {
        var iter2 = toot.tagList.iterator();
        while(iter2.next()) |toot_tag| {
          if(std.mem.compare(u8, filter_tag, toot_tag) == std.mem.Compare.Equal) {
            return true;
          }
        }
      }
      return false;
    }
  }
};

pub fn parse(allocator: *Allocator, lang: []const u8) *ptree {
  var newTree = allocator.create(ptree) catch unreachable;
  newTree.tags = allocator.create(toot_lib.Type.TagList) catch unreachable;
  newTree.tags.* = toot_lib.Type.TagList.init(allocator);
  var spaceParts = std.mem.tokenize(lang, " ");
  var idx = usize(0);
  while (spaceParts.next()) |part| {
    idx += 1;
    if(idx == 1) {
      newTree.hostname = part;
      warn("filter set host {}\n", part);
    }
    if(idx > 1) {
      newTree.tags.append(part) catch unreachable;
      warn("filter set tag #{} {}\n", newTree.tags.len, part);
    }
  }
  return newTree;
}
