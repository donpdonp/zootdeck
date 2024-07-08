const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const Node = c.GumboNode;

const c = @cImport({
    @cInclude("gumbo.h");
});

pub fn parse(html: []const u8) *Node {
    // const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL, 8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML};
    var options = c.GumboOptions{
        .allocator = c.kGumboDefaultOptions.allocator,
        .deallocator = c.kGumboDefaultOptions.deallocator,
        .userdata = null,
        .tab_stop = 8,
        .stop_on_first_error = false,
        .max_errors = -1,
        .fragment_context = c.GUMBO_TAG_BODY,
        .fragment_namespace = c.GUMBO_NAMESPACE_HTML,
    };
    const doc = c.gumbo_parse_with_options(&options, html.ptr, html.len);
    const root = doc.*.root;
    //var tagType = root.*.type;
    //var tagName = root.*.v.element.tag;
    return root;
}

pub fn search(node: *Node) void {
    if (node.type == c.GUMBO_NODE_ELEMENT) {
        if (node.v.element.tag == c.GUMBO_TAG_A) {
            //warn("A TAG found\n");
        }
        const children = node.v.element.children;
        var idx = @as(u32, @intCast(0));
        while (idx < children.length) : (idx += 1) {
            const cnode = children.data[idx];
            if (cnode) |chld| {
                search(@as(*Node, @ptrCast(@alignCast(chld))));
            }
        }
    }
}
