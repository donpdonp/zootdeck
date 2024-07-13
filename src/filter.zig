// filter.zig
const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const util = @import("util.zig");
const string = []const u8;
const toot_lib = @import("toot.zig");

const c = @cImport({
    @cInclude("ragel/lang.h");
});

pub const ptree = struct {
    hostname: string,
    tags: *toot_lib.Type.TagList,

    const Self = @This();

    pub fn host(self: *const Self) []const u8 {
        return self.hostname;
    }

    pub fn match(self: *const Self, toot: *toot_lib.Type) bool {
        if (self.tags.items.len == 0) {
            return true;
        } else {
            for (self.tags.items) |filter_tag| {
                for (toot.tagList.items) |toot_tag| {
                    if (std.mem.order(u8, filter_tag, toot_tag) == std.math.Order.eq) {
                        return true;
                    }
                }
            }
            return false;
        }
    }
};

pub fn parse(allocator: Allocator, lang: []const u8) *ptree {
    var ragel_points = c.urlPoints{ .scheme_pos = 0, .loc_pos = 0 };
    const clang = util.sliceToCstr(allocator, lang);
    _ = c.url(clang, &ragel_points);
    warn("ragel parse \"{s}\"\n", .{lang});

    var newTree = allocator.create(ptree) catch unreachable;
    newTree.tags = allocator.create(toot_lib.Type.TagList) catch unreachable;
    newTree.tags.* = toot_lib.Type.TagList.init(allocator);
    var spaceParts = std.mem.tokenize(u8, lang, " ");
    var idx: usize = 0;
    while (spaceParts.next()) |part| {
        idx += 1;
        if (idx == 1) {
            newTree.hostname = part;
            warn("filter set host {s}\n", .{part});
        }
        if (idx > 1) {
            newTree.tags.append(part) catch unreachable;
            warn("filter set tag #{!} {s}\n", .{ newTree.tags.items.len, part });
        }
    }
    return newTree;
}
