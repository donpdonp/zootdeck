const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const allocator = std.heap.c_allocator;

const Node = c.GumboNode;

const c = @cImport({
  @cInclude("gumbo.h");
});

pub fn parse(html: []const u8) *Node {
  //return HtmlTree.init();
  var doc = c.gumbo_parse(c"");
  var root = doc.*.root;
  var tagType = root.*.type;
  var tagName = root.*.v.element.tag;
  warn("parsed: {}\n", html);
  return root;
}

pub fn search(node: *Node) void {
  if (node.type == c.GumboNodeType.GUMBO_NODE_ELEMENT) {
    warn("SearchStart {*} {}\n", node, node.v.element.tag);
    if(node.v.element.tag == c.GumboTag.GUMBO_TAG_A) {
      warn("A TAG found\n");
    }
    var children = node.v.element.children;
    warn("children len {}\n", children.length);
    var idx = u32(0);
    while(idx < children.length) : (idx += 1) {
      const cnode = children.data[idx];
      warn("child {*}\n", cnode);
      if(cnode) |chld| {
        search(@ptrCast(*Node, @alignCast(8, chld)));
      }
    }
  }
}