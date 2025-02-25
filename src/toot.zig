// toot.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const util = @import("util.zig");
const warn = util.log;

pub const Type = Toot();

pub fn Toot() type {
    return struct {
        hashmap: std.json.Value,
        tagList: TagList,
        imgList: ImgList,

        const Self = @This();
        const TagType = []const u8;
        pub const TagList = std.ArrayList(TagType);
        const ImgType = []const u8;
        const ImgList = std.ArrayList(ImgType);
        const K = []const u8;
        const V = std.json.Value;
        pub fn init(hash: std.json.Value, allocator: Allocator) *Self {
            var toot = allocator.create(Self) catch unreachable;
            toot.hashmap = hash;
            toot.tagList = TagList.init(allocator);
            toot.imgList = ImgList.init(allocator);
            toot.parseTags(allocator);
            warn("toot init #{s}", .{toot.id()});
            return toot;
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.hashmap.object.get(key);
        }

        pub fn id(self: *const Self) []const u8 {
            if (self.hashmap.object.get("id")) |kv| {
                return kv.string;
            } else {
                unreachable;
            }
        }

        pub fn acct(self: *const Self) ![]const u8 {
            if (self.hashmap.object.get("account")) |kv| {
                if (kv.object.get("acct")) |akv| {
                    return akv.string;
                } else {
                    return error.NoAcct;
                }
            } else {
                return error.NoAccount;
            }
        }

        pub fn content(self: *const Self) []const u8 {
            return self.hashmap.object.get("content").?.string;
        }

        pub fn parseTags(self: *Self, allocator: Allocator) void {
            const hDecode = util.htmlEntityDecode(self.content(), allocator) catch unreachable;
            const html_trim = util.htmlTagStrip(hDecode, allocator) catch unreachable;

            var wordParts = std.mem.tokenize(u8, html_trim, " ");
            while (wordParts.next()) |word| {
                if (std.mem.startsWith(u8, word, "#")) {
                    self.tagList.append(word) catch unreachable;
                }
            }
        }

        pub fn addImg(self: *Self, imgdata: ImgType) void {
            warn("addImg toot {s}", .{self.id()});
            self.imgList.append(imgdata) catch unreachable;
        }

        pub fn imgCount(self: *Self) usize {
            const images = self.hashmap.object.get("media_attachments").?.array;
            return images.items.len;
        }
    };
}

test "Toot" {
    const allocator = std.testing.allocator;
    var tootHash = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };

    var jString = std.json.Value{ .string = "ABC" };
    _ = tootHash.object.put("content", jString) catch unreachable;

    var toot = Type.init(&tootHash, allocator);
    try testing.expect(toot.tagList.items.len == 0);
    warn("toot1 {*}\n", &toot);

    jString.string = "ABC   #xyz";
    _ = tootHash.object.put("content", jString) catch unreachable;
    const toot2 = Type.init(&tootHash, allocator);
    warn("toot2 {*}\n", &toot2);
    try testing.expect(toot2.tagList.items.len == 1);
    try testing.expect(std.mem.order(u8, toot2.tagList.items[0], "#xyz") == std.math.Order.eq);
}
