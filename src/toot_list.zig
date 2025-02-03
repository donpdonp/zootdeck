// toot_list.zig
const std = @import("std");
const Allocator = std.mem.Allocator;

const toot_lib = @import("./toot.zig");
const util = @import("./util.zig");
const warn = util.log;

pub const TootList = SomeList(*toot_lib.Type);

pub fn SomeList(comptime T: type) type {
    return struct {
        list: ListType,

        const Self = @This();
        const ListType = std.DoublyLinkedList(T);

        pub fn init() Self {
            return Self{
                .list = ListType{},
            };
        }

        pub fn len(self: *Self) usize {
            return self.list.len;
        }

        pub fn first(self: *Self) ?*ListType.Node {
            return self.list.first;
        }

        pub fn contains(self: *Self, item: T) bool {
            var ptr = self.list.first;
            while (ptr) |listItem| {
                if (util.hashIdSame(T, listItem.data, item)) {
                    return true;
                }
                ptr = listItem.next;
            }
            return false;
        }

        pub fn author(self: *Self, acct: []const u8, allocator: Allocator) []T {
            var winners = std.ArrayList(T).init(allocator);
            var ptr = self.list.first;
            while (ptr) |listItem| {
                const toot = listItem.data;
                if (toot.author(acct)) {
                    winners.append(toot) catch unreachable;
                }
                ptr = listItem.next;
            }
            return winners.items;
        }

        pub fn sortedInsert(self: *Self, item: T, allocator: Allocator) void {
            const itemDate = item.get("created_at").?.string;
            const node = allocator.create(ListType.Node) catch unreachable;
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
                warn("#{} tlist {*}", .{ counter, item.data });
                counter = counter + 1;
                current = item.next;
            }
            return counter;
        }
    };
}
