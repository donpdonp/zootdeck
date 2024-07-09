const std = @import("std");

pub const SimpleU8 = struct {
    list: std.ArrayList(u8),

    pub fn initSize(allocator: std.mem.Allocator, size: usize) !SimpleU8 {
        var self = SimpleU8{ .list = std.ArrayList(u8).init(allocator) };
        try self.resize(size);
        return self;
    }

    pub fn len(self: *const SimpleU8) usize {
        return self.list.items.len;
    }

    pub fn resize(self: *SimpleU8, new_len: usize) !void {
        try self.list.resize(new_len);
    }

    pub fn toSliceConst(self: *const SimpleU8) []const u8 {
        return self.list.items[0..self.len()];
    }

    pub fn append(self: *SimpleU8, m: []const u8) !void {
        const old_len = self.len();
        try self.resize(old_len + m.len);
        std.mem.copyForwards(u8, self.list.items[old_len..], m);
    }

    pub fn appendByte(self: *SimpleU8, byte: u8) !void {
        const old_len = self.len();
        try self.resize(old_len + 1);
        self.list.items[old_len] = byte;
    }
};
