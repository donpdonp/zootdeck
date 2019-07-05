const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const allocator = std.heap.c_allocator;


const c = @cImport({
  @cInclude("gumbo.h");
});


pub fn parse(html: []const u8) void {
  //return HtmlTree.init();
  var doc = c.gumbo_parse(c"");
}
