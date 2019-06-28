// auth.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const simple_buffer = @import("./simple_buffer.zig");
const config = @import("./config.zig");

pub fn oauthUrl(allocator: *Allocator, httpInfo: *config.HttpInfo, url: []const u8) void {
  var urlBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  urlBuf.append("https://") catch unreachable;
  urlBuf.append(url) catch unreachable;
  urlBuf.append("/api/v1/apps") catch unreachable;
  httpInfo.url = urlBuf.toSliceConst();
  var postBodyBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  postBodyBuf.append("client_name=zootdeck") catch unreachable;
  postBodyBuf.append("&scopes=read+write") catch unreachable;
  postBodyBuf.append("&redirect_uris=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
  httpInfo.post_body = postBodyBuf.toSliceConst();
}