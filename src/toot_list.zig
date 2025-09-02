// toot_list.zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const toot_lib = @import("./toot.zig");
const util = @import("./util.zig");
const warn = util.log;

pub const Node = struct {
    node: std.DoublyLinkedList.Node,
    data: *toot_lib.Toot,
};

pub const TootList = struct {
    date_index: std.DoublyLinkedList,
    list: std.array_list.Managed(*toot_lib.Toot),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{ .date_index = .{}, .list = .init(allocator) };
    }

    pub fn len(self: *Self) usize {
        return self.list.len;
    }

    pub fn contains(self: *Self, item: *toot_lib.Toot) bool {
        var ptr = self.date_index.first;
        while (ptr) |list_item_node| {
            const list_item: *Node = @fieldParentPtr("node", list_item_node);
            if (util.hashIdSame(*toot_lib.Toot, list_item.data, item)) {
                return true;
            }
            ptr = list_item_node.next;
        }
        return false;
    }

    pub fn author(self: *Self, acct: []const u8, allocator: Allocator) []*toot_lib.Toot {
        var winners = std.array_list.Managed(*toot_lib.Toot).init(allocator);
        var ptr = self.date_index.first;
        while (ptr) |list_item_node| {
            const list_item: *Node = @fieldParentPtr("node", list_item_node);
            const toot = list_item.data;
            if (toot.acct()) |toot_acct| {
                if (std.mem.order(u8, acct, toot_acct) == std.math.Order.eq) {
                    winners.append(toot) catch unreachable;
                }
            } else |_| {}
            ptr = list_item_node.next;
        }
        return winners.items;
    }

    pub fn sortedInsert(self: *Self, item: *toot_lib.Toot, allocator: Allocator) void {
        const itemDate = item.get("created_at").?.string;
        const node = allocator.create(Node) catch unreachable;
        node.data = item;
        var current = self.date_index.first;
        while (current) |list_item_node| {
            const list_item: *Node = @fieldParentPtr("node", list_item_node);
            const listItemDate = list_item.data.get("created_at").?.string;
            if (std.mem.order(u8, itemDate, listItemDate) == std.math.Order.gt) {
                self.date_index.insertBefore(&list_item.node, &node.node);
                return;
            } else {}
            current = list_item.node.next;
        }
        self.list.append(item) catch unreachable;
    }

    pub fn count(self: *Self) usize {
        return self.list.items.len;
    }
};
