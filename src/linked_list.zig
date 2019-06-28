const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Generic doubly linked list.
pub fn LinkedList(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Node inside the linked list wrapping the actual data.
        pub const Node = struct {
            prev: ?*Node,
            next: ?*Node,
            data: T,

            pub fn init(data: T) Node {
                return Node{
                    .prev = null,
                    .next = null,
                    .data = data,
                };
            }
        };

        first: ?*Node,
        last: ?*Node,
        len: usize,

        /// Initialize a linked list.
        ///
        /// Returns:
        ///     An empty linked list.
        pub fn init() Self {
            return Self{
                .first = null,
                .last = null,
                .len = 0,
            };
        }

        /// Insert a new node after an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertAfter(list: *Self, node: *Node, new_node: *Node) void {
            new_node.prev = node;
            if (node.next) |next_node| {
                // Intermediate node.
                new_node.next = next_node;
                next_node.prev = new_node;
            } else {
                // Last element of the list.
                new_node.next = null;
                list.last = new_node;
            }
            node.next = new_node;

            list.len += 1;
        }

        /// Insert a new node before an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
            new_node.next = node;
            if (node.prev) |prev_node| {
                // Intermediate node.
                new_node.prev = prev_node;
                prev_node.next = new_node;
            } else {
                // First element of the list.
                new_node.prev = null;
                list.first = new_node;
            }
            node.prev = new_node;

            list.len += 1;
        }

        /// Concatenate list2 onto the end of list1, removing all entries from the former.
        ///
        /// Arguments:
        ///     list1: the list to concatenate onto
        ///     list2: the list to be concatenated
        pub fn concatByMoving(list1: *Self, list2: *Self) void {
            const l2_first = list2.first orelse return;
            if (list1.last) |l1_last| {
                l1_last.next = list2.first;
                l2_first.prev = list1.last;
                list1.len += list2.len;
            } else {
                // list1 was empty
                list1.first = list2.first;
                list1.len = list2.len;
            }
            list1.last = list2.last;
            list2.first = null;
            list2.last = null;
            list2.len = 0;
        }

        /// Insert a new node at the end of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn append(list: *Self, new_node: *Node) void {
            if (list.last) |last| {
                // Insert after last.
                list.insertAfter(last, new_node);
            } else {
                // Empty list.
                list.prepend(new_node);
            }
        }

        /// Insert a new node at the beginning of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn prepend(list: *Self, new_node: *Node) void {
            if (list.first) |first| {
                // Insert before first.
                list.insertBefore(first, new_node);
            } else {
                // Empty list.
                list.first = new_node;
                list.last = new_node;
                new_node.prev = null;
                new_node.next = null;

                list.len = 1;
            }
        }

        /// Remove a node from the list.
        ///
        /// Arguments:
        ///     node: Pointer to the node to be removed.
        pub fn remove(list: *Self, node: *Node) void {
            if (node.prev) |prev_node| {
                // Intermediate node.
                prev_node.next = node.next;
            } else {
                // First element of the list.
                list.first = node.next;
            }

            if (node.next) |next_node| {
                // Intermediate node.
                next_node.prev = node.prev;
            } else {
                // Last element of the list.
                list.last = node.prev;
            }

            list.len -= 1;
            assert(list.len == 0 or (list.first != null and list.last != null));
        }

        /// Remove and return the last node in the list.
        ///
        /// Returns:
        ///     A pointer to the last node in the list.
        pub fn pop(list: *Self) ?*Node {
            const last = list.last orelse return null;
            list.remove(last);
            return last;
        }

        /// Remove and return the first node in the list.
        ///
        /// Returns:
        ///     A pointer to the first node in the list.
        pub fn popFirst(list: *Self) ?*Node {
            const first = list.first orelse return null;
            list.remove(first);
            return first;
        }

        /// Allocate a new node.
        ///
        /// Arguments:
        ///     allocator: Dynamic memory allocator.
        ///
        /// Returns:
        ///     A pointer to the new node.
        pub fn allocateNode(list: *Self, allocator: *Allocator) !*Node {
            return allocator.create(Node);
        }

        /// Deallocate a node.
        ///
        /// Arguments:
        ///     node: Pointer to the node to deallocate.
        ///     allocator: Dynamic memory allocator.
        pub fn destroyNode(list: *Self, node: *Node, allocator: *Allocator) void {
            allocator.destroy(node);
        }

        /// Allocate and initialize a node and its data.
        ///
        /// Arguments:
        ///     data: The data to put inside the node.
        ///     allocator: Dynamic memory allocator.
        ///
        /// Returns:
        ///     A pointer to the new node.
        pub fn createNode(list: *Self, data: T, allocator: *Allocator) !*Node {
            var node = try list.allocateNode(allocator);
            node.* = Node.init(data);
            return node;
        }
    };
}

test "basic linked list test" {
    const allocator = debug.global_allocator;
    var list = LinkedList(u32).init();

    var one = try list.createNode(1, allocator);
    var two = try list.createNode(2, allocator);
    var three = try list.createNode(3, allocator);
    var four = try list.createNode(4, allocator);
    var five = try list.createNode(5, allocator);
    defer {
        list.destroyNode(one, allocator);
        list.destroyNode(two, allocator);
        list.destroyNode(three, allocator);
        list.destroyNode(four, allocator);
        list.destroyNode(five, allocator);
    }

    list.append(two); // {2}
    list.append(five); // {2, 5}
    list.prepend(one); // {1, 2, 5}
    list.insertBefore(five, four); // {1, 2, 4, 5}
    list.insertAfter(two, three); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    var first = list.popFirst(); // {2, 3, 4, 5}
    var last = list.pop(); // {2, 3, 4}
    list.remove(three); // {2, 4}

    testing.expect(list.first.?.data == 2);
    testing.expect(list.last.?.data == 4);
    testing.expect(list.len == 2);
}

test "linked list concatenation" {
    const allocator = debug.global_allocator;
    var list1 = LinkedList(u32).init();
    var list2 = LinkedList(u32).init();

    var one = try list1.createNode(1, allocator);
    defer list1.destroyNode(one, allocator);
    var two = try list1.createNode(2, allocator);
    defer list1.destroyNode(two, allocator);
    var three = try list1.createNode(3, allocator);
    defer list1.destroyNode(three, allocator);
    var four = try list1.createNode(4, allocator);
    defer list1.destroyNode(four, allocator);
    var five = try list1.createNode(5, allocator);
    defer list1.destroyNode(five, allocator);

    list1.append(one);
    list1.append(two);
    list2.append(three);
    list2.append(four);
    list2.append(five);

    list1.concatByMoving(&list2);

    testing.expect(list1.last == five);
    testing.expect(list1.len == 5);
    testing.expect(list2.first == null);
    testing.expect(list2.last == null);
    testing.expect(list2.len == 0);

    // Traverse forwards.
    {
        var it = list1.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list1.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    // Swap them back, this verifies that concating to an empty list works.
    list2.concatByMoving(&list1);

    // Traverse forwards.
    {
        var it = list2.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list2.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            testing.expect(node.data == (6 - index));
            index += 1;
        }
    }
}
