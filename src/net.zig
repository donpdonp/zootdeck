// net.zig
const std = @import("std");
const thread = @import("./thread.zig");

const config = @import("./config.zig");
const util = @import("./util.zig");

const warn = util.log;

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("pthread.h");
    @cInclude("curl/curl.h");
});

const NetError = error{ JSONparse, Curl, CurlInit, DNS };

pub fn go(data: ?*anyopaque) callconv(.C) ?*anyopaque {
    var actor = @as(*thread.Actor, @ptrCast(@alignCast(data)));
    //warn("net thread start {*} {}\n", actor, actor);

    // setup for the callback
    var command = actor.allocator.create(thread.Command) catch unreachable;
    command.id = 1;
    command.verb = actor.payload;

    if (httpget(actor.allocator, actor.payload.http)) |body| {
        actor.payload.http.body = body;
    } else |err| {
        warn("net.go http {!} #{}", .{ err, actor.payload.http.response_code });
    }
    thread.signal(actor, command);
    return null;
}

pub fn httpget(allocator: std.mem.Allocator, req: *config.HttpInfo) ![]const u8 {
    _ = c.curl_global_init(0);
    const curl = c.curl_easy_init();
    if (curl != null) {
        const cstr = util.sliceAddNull(allocator, req.url);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, cstr.ptr);

        const zero: c_long = 0;
        const seconds: c_long = 30;
        _ = c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT, seconds);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYPEER, zero);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYHOST, zero);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, curl_write);
        var body_buffer = std.ArrayList(u8).init(allocator);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &body_buffer);

        //var slist: ?[*c]c.curl_slist = null;
        var slist = @as([*c]c.curl_slist, @ptrFromInt(0)); // 0= new list
        slist = c.curl_slist_append(slist, "Accept: application/json");
        if (req.token) |_| {
            //warn("Authorization: {s}\n", .{token});
        }
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, slist);

        switch (req.verb) {
            .get => _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPGET, @as(c_long, 1)),
            .post => {
                _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
                const post_body_c: [*c]const u8 = util.sliceToCstr(allocator, req.post_body);
                _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, post_body_c);
                //warn("post body: {s}\n", .{req.post_body});
            },
        }

        const res = c.curl_easy_perform(curl);
        defer c.curl_easy_cleanup(curl);
        if (res == c.CURLE_OK) {
            _ = c.curl_easy_getinfo(curl, c.CURLINFO_RESPONSE_CODE, &req.response_code);
            var ccontent_type: [*c]const u8 = undefined;
            _ = c.curl_easy_getinfo(curl, c.CURLINFO_CONTENT_TYPE, &ccontent_type);
            req.content_type = util.cstrToSliceCopy(allocator, ccontent_type);
            util.log("# {s} {s} {} bytes", .{
                req.url,
                req.content_type,
                body_buffer.items.len,
            });
            return body_buffer.toOwnedSliceSentinel(0);
        } else if (res == c.CURLE_OPERATION_TIMEDOUT) {
            req.response_code = 2200;
            return NetError.Curl;
        } else {
            //const err_cstr = c.curl_easy_strerror(res);
            //warn("curl ERR {!} {s}\n", .{ res, util.cstrToSliceCopy(allocator, err_cstr) });
            if (res == c.CURLE_COULDNT_RESOLVE_HOST) {
                req.response_code = 2100;
                return NetError.DNS;
            } else {
                req.response_code = 2000;
                warn("net.go unknown curl result code {}", .{res});
                return NetError.Curl;
            }
        }
    } else {
        //warn("net curl easy init fail\n", .{});
        return NetError.CurlInit;
    }
}

pub fn curl_write(ptr: [*c]const u8, _: usize, nmemb: usize, userdata: *anyopaque) callconv(.C) usize {
    var buf = @as(*std.ArrayList(u8), @ptrCast(@alignCast(userdata)));
    const body_part: []const u8 = ptr[0..nmemb];
    buf.appendSlice(body_part) catch {};
    return nmemb;
}
