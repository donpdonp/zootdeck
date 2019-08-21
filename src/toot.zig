// toot.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;
const testing = std.testing;

const util = @import("util.zig");
const json_lib = @import("json.zig");

pub const Type = Toot();

pub fn Toot() type {
  return struct {
    hashmap: Toothashmap,
    tagList: TagList,
    imgList: ImgList,

    const Self = @This();
    const TagType = []const u8;
    const TagList = std.ArrayList(TagType);
    const ImgType = []const u8;
    const ImgList = std.ArrayList(ImgType);
    const K = []const u8;
    const V = std.json.Value;
    const Toothashmap = std.hash_map.HashMap(K, V,
                                             std.mem.hash_slice_u8,
                                             std.mem.eql_slice_u8);
    pub fn init(hash: Toothashmap, allocator: *Allocator) Self {
     var newToot = Self{
        .hashmap = hash,
        .tagList = TagList.init(allocator),
        .imgList = ImgList.init(allocator)
      };
      newToot.parseTags(allocator);
      return newToot;
    }

    pub fn get(self: *const Self, key: K) ?*Toothashmap.KV {
      return self.hashmap.get(key);
    }

    pub fn id(self: *const Self) []const u8 {
      if(self.hashmap.get("id")) |kv| {
        return kv.value.String;
      } else {
        unreachable;
      }
    }

    pub fn author(self: *const Self, acct: []const u8) bool {
      if(self.hashmap.get("account")) |kv| {
        if(kv.value.Object.get("acct")) |akv| {
          const existing_acct = akv.value.String;
          return std.mem.compare(u8, acct, existing_acct) == std.mem.Compare.Equal;
        } else {
          return false;
        }
      } else {
        return false;
      }
    }

    pub fn content(self: *const Self) []const u8 {
      return self.hashmap.get("content").?.value.String;
    }

    pub fn parseTags(self: *Self, allocator: *Allocator) void {
      const content_zig_namespace_yuk = self.content();
      const jDecode = json_lib.jsonStrDecode(content_zig_namespace_yuk, allocator)  catch unreachable;
      const hDecode = util.htmlEntityDecode(jDecode, allocator)  catch unreachable;
      const html_trim = util.htmlTagStrip(hDecode, allocator) catch unreachable;

      var wordParts = std.mem.tokenize(html_trim, " ");
      while (wordParts.next()) |word| {
        if(std.mem.startsWith(u8, word, "#")) {
          self.tagList.append(word) catch unreachable;
        }
      }
    }

    pub fn addImg(self: *Self, imgdata: ImgType) void {
      warn("addImg toot {*}\n", self);
      self.imgList.append(imgdata) catch unreachable;
    }

    pub fn imgCount(self: *Self) usize {
      return self.imgList.count();
    }
  };
}

test "Toot" {
  var bytes: [8096]u8 = undefined;
  const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
  var tootHash = Type.Toothashmap.init(allocator);

  var jString = std.json.Value{ .String = "" };
  _ = tootHash.put("content", jString) catch unreachable;

  jString.String = "ABC";
  _ = tootHash.put("content", jString) catch unreachable;
  var toot = Type.init(tootHash, allocator);
  testing.expect(toot.tagList.count() == 0);
  warn("toot1 {*}\n", &toot);

  jString.String = "ABC   #xyz";
  _ = tootHash.put("content", jString) catch unreachable;
  const toot2 = Type.init(tootHash, allocator);
  warn("toot2 {*}\n", &toot2);
  testing.expect(toot2.tagList.count() == 1);
  testing.expect(std.mem.compare(u8, toot2.tagList.at(0), "#xyz") == std.mem.Compare.Equal);
}

