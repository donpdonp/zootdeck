// net.zig
const std = @import("std");
const thread = @import("./thread.zig");
const allocator = std.heap.c_allocator; // passing through pthread nope

const config = @import("./config.zig");
const util = @import("./util.zig");

const warn = std.debug.warn;

const c = @cImport({
  @cInclude("unistd.h");
  @cInclude("pthread.h");
  @cInclude("curl/curl.h");
});

const NetError = error{
  JSONparse,
  Curl,
  CurlInit,
  DNS
};

pub extern fn go(data: ?*c_void) ?*c_void {
  var data8 = @alignCast(@alignOf(thread.Actor), data);
  var actor = @ptrCast(*thread.Actor, data8);
  warn("net thread start {*} {}\n", actor, actor);

  // setup for the callback
  var command = allocator.create(thread.Command) catch unreachable;
  command.id = 1;
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  command.verb = actor.payload;

  if (httpget(actor.payload.http)) |body| {
    const maxlen = if(body.len > 400) 400 else body.len;
    warn("net http byte {} bytes {}\n", body.len, body[0..maxlen]);
    actor.payload.http.body = body;
    if(body.len > 0) {
      var json_parser = std.json.Parser.init(allocator, false);
      if(json_parser.parse(body)) |value_tree| {
        actor.payload.http.tree = value_tree;
      } else |err| {
        warn("net json err {}\n", err);
        actor.payload.http.response_code = 1000;
      }
    }
  } else |err| {
      warn("net thread http err {}\n", err);
  }
  thread.signal(actor, command);
  return null;
}

pub fn httpget(req: *config.HttpInfo) ![]const u8 {
    warn("http {} {} {}\n", req.verb, req.url, if(req.token) |tk| "token" else "");
    _ = c.curl_global_init(0);
    var curl = c.curl_easy_init();
    if (curl != null) {
        var cstr = std.cstr.addNullByte(allocator, req.url) catch unreachable;
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_URL, cstr.ptr);

        var zero: c_long = 0;
        var seconds: c_long = 30;
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_CONNECTTIMEOUT, seconds);
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_SSL_VERIFYPEER, zero);
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_SSL_VERIFYHOST, zero);
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_WRITEFUNCTION, curl_write);
        var body_buffer = try std.Buffer.initSize(allocator, 0);
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_WRITEDATA, &body_buffer);

        //var slist: ?[*c]c.curl_slist = null;
        var slist = @intToPtr([*c]c.curl_slist, 0); // 0= new list
        slist = c.curl_slist_append(slist, c"Accept: application/json");
        if(req.token) |token| {
          warn("Authorization: {}\n", token);
          var authbuf = allocator.alloc(u8, 256) catch unreachable;
          var authstr = std.fmt.bufPrint(authbuf, "Authorization: bearer {}", token) catch unreachable;
          var cauthstr = util.sliceToCstr(allocator, authstr);
          slist = c.curl_slist_append(slist, cauthstr);
        }
        _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_HTTPHEADER, slist);

        switch(req.verb) {
          .get => _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_HTTPGET, c_long(1)),
          .post => {
            _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_POST, c_long(1));
            const post_body_c: [*c]const u8 = util.sliceToCstr(allocator, req.post_body);
            _ = c.curl_easy_setopt(curl, c.CURLoption.CURLOPT_POSTFIELDS, post_body_c);
            warn("post body: {}\n", req.post_body);
          }
        }

        var res = c.curl_easy_perform(curl);
        if (res == c.CURLcode.CURLE_OK) {
          var http_status: c_long = undefined;
          _ = c.curl_easy_getinfo(curl, c.CURLINFO.CURLINFO_RESPONSE_CODE, &http_status);
          req.response_code = http_status;
          warn("net curl OK {}\n", http_status);
          return body_buffer.toOwnedSlice();
        } else if (res == c.CURLcode.CURLE_OPERATION_TIMEDOUT) {
          req.response_code = 2200;
          return NetError.Curl;
        } else {
          const err_cstr = c.curl_easy_strerror(res);
          warn("curl ERR {} {}\n", res, std.cstr.toSliceConst(err_cstr));
          if(res == c.CURLcode.CURLE_COULDNT_RESOLVE_HOST) {
            req.response_code = 2100;
            return NetError.DNS;
          } else {
            req.response_code = 2000;
            return NetError.Curl;
          }
        }
        c.curl_easy_cleanup(curl);
    } else {
        warn("net curl easy init fail\n");
        return NetError.CurlInit;
    }
}

pub fn curl_write(ptr: [*c]const u8, size: usize, nmemb: usize, userdata: *c_void) usize {
  var buf = @ptrCast(*std.Buffer, @alignCast(8,userdata));
  var body_part: []const u8 = ptr[0..nmemb];
  buf.append(body_part) catch |err| {warn("curl_write append fail\n");};
  return nmemb;
}
