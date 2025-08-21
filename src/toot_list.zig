// toot_list.zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const toot_lib = @import("./toot.zig");
const util = @import("./util.zig");
const warn = util.log;

pub const TootListNode = struct {
    node: std.DoublyLinkedList.Node,
    data: *toot_lib.Type,
};

pub const TootList = struct {
    list: std.DoublyLinkedList,

    const Self = @This();

    pub fn len(self: *Self) usize {
        return self.list.len;
    }

    pub fn first(self: *Self) std.DoublyLinkedList.Node {
        return self.list.first;
    }

    pub fn contains(self: *Self, item: TootListNode) bool {
        var ptr = self.list.first;
        while (ptr) |listItem| {
            if (util.hashIdSame(TootListNode, listItem.data, item)) {
                return true;
            }
            ptr = listItem.next;
        }
        return false;
    }

    pub fn author(self: *Self, acct: []const u8, allocator: Allocator) []TootListNode {
        var winners = std.ArrayList(TootListNode).init(allocator);
        var ptr = self.list.first;
        while (ptr) |listItem| {
            const toot = listItem.data;
            if (toot.acct()) |toot_acct| {
                if (std.mem.order(u8, acct, toot_acct) == std.math.Order.eq) {
                    winners.append(toot) catch unreachable;
                }
            } else |_| {}
            ptr = listItem.next;
        }
        return winners.items;
    }

    pub fn sortedInsert(self: *Self, item: TootListNode, allocator: Allocator) void {
        const itemDate = item.get("created_at").?.string;
        const node = allocator.create(TootListNode.Node) catch unreachable;
        node.data = item;
        var current = self.list.first;
        while (current) |listItem| {
            const listItemDate = listItem.data.get("created_at").?.string;
            if (std.mem.order(u8, itemDate, listItemDate) == std.math.Order.gt) {
                self.list.insertBefore(listItem, node);
                return;
            } else {}
            current = listItem.next;
        }
        self.list.append(node);
    }

    pub fn count(self: *Self) usize {
        var counter: usize = 0;
        var current = self.list.first;
        while (current) |item| {
            counter = counter + 1;
            current = item.next;
        }
        return counter;
    }
};
