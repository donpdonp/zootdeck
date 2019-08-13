// filter.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const string = []const u8;

pub const ptree = struct {
  hostname: string,
  tags: *std.ArrayList(string),

  const Self = @This();

  pub fn host(self: *const Self) []const u8 {
    return self.hostname;
  }
};

pub fn parse(allocator: *Allocator, lang: []const u8) *ptree {
  var newTree = allocator.create(ptree) catch unreachable;
  var tagList = std.ArrayList(string).init(allocator);
  newTree.tags = &tagList;
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
