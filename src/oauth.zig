// auth.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const SimpleBuffer = @import("./simple_buffer.zig");
const config = @import("./config.zig");

pub fn clientRegisterUrl(allocator: Allocator, httpInfo: *config.HttpInfo, url: []const u8) void {
    var urlBuf = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
    urlBuf.append("https://") catch unreachable;
    urlBuf.append(url) catch unreachable;
    urlBuf.append("/api/v1/apps") catch unreachable;
    httpInfo.url = urlBuf.toSliceConst();
    var postBodyBuf = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
    postBodyBuf.append("client_name=zootdeck") catch unreachable;
    postBodyBuf.append("&scopes=read+write") catch unreachable;
    postBodyBuf.append("&redirect_uris=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
    httpInfo.post_body = postBodyBuf.toSliceConst();
}

pub fn tokenUpgradeUrl(allocator: Allocator, httpInfo: *config.HttpInfo, url: []const u8, code: []const u8, clientId: []const u8, clientSecret: []const u8) void {
    var urlBuf = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
    urlBuf.append("https://") catch unreachable;
    urlBuf.append(url) catch unreachable;
    urlBuf.append("/oauth/token") catch unreachable;
    httpInfo.url = urlBuf.toSliceConst();
    var postBodyBuf = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
    postBodyBuf.append("client_id=") catch unreachable;
    postBodyBuf.append(clientId) catch unreachable;
    postBodyBuf.append("&client_secret=") catch unreachable;
    postBodyBuf.append(clientSecret) catch unreachable;
    postBodyBuf.append("&grant_type=authorization_code") catch unreachable;
    postBodyBuf.append("&code=") catch unreachable;
    postBodyBuf.append(code) catch unreachable;
    postBodyBuf.append("&redirect_uri=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
    httpInfo.post_body = postBodyBuf.toSliceConst();
}
