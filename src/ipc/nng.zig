// net.zig
const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
const std_allocator = std.heap.c_allocator; // passing through pthread nope
const util = @import("./util.zig");

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("nng/nng.h");
    @cInclude("nng/protocol/pair0/pair.h");
    @cInclude("nng/transport/ipc/ipc.h");
});

pub const sock = c.nng_socket;

pub const Client = struct { srv: *sock, clnt: *sock };

const Url = "ipc:///tmp/nng-pair-";

pub fn init() void {}

pub fn listen(socket: *sock, url: []u8) void {
    warn("nng master listen {} {}\n", socket, url);
    if (c.nng_listen(socket.*, util.sliceToCstr(std_allocator, url), @as([*c]c.struct_nng_listener_s, @ptrFromInt(0)), 0) != 0) {
        warn("nng_listen FAIL\n");
    }
}

pub fn wait(client: *Client, callback: fn (?*anyopaque) callconv(.C) void) void {
    // special nng alloc call
    var myAio: ?*c.nng_aio = undefined;
    warn("wait master nng_aio {*}\n", &myAio);
    var message = std_allocator.alloc(u8, 4) catch unreachable;
    message[0] = 'H';
    message[1] = 2;
    message[2] = 1;
    message[3] = 0;
    _ = c.nng_aio_alloc(&myAio, callback, @as(?*anyopaque, @ptrCast(&message)));
    warn("wait master nng_aio post {*}\n", myAio);

    warn("wait master nng_recv {}\n", client.srv);
    c.nng_recv_aio(client.srv.*, myAio);
}

pub fn dial(socket: *sock, url: []u8) void {
    warn("nng dial {} {s}\n", socket, util.sliceToCstr(std_allocator, url));
    if (c.nng_dial(socket.*, util.sliceToCstr(std_allocator, url), @as([*c]c.struct_nng_dialer_s, @ptrFromInt(0)), 0) != 0) {
        warn("nng_pair0_dial FAIL\n");
    }
}

pub fn newClient(allocator: *Allocator) *Client {
    const client = allocator.create(Client) catch unreachable;
    var url_buf: [256]u8 = undefined;
    const myUrl = std.fmt.bufPrint(url_buf[0..], "{}{*}", Url, client) catch unreachable;
    warn("newClient {}\n", myUrl);
    const socket = allocator.create(sock) catch unreachable;
    client.srv = socket;
    var nng_ret = c.nng_pair0_open(client.srv);
    if (nng_ret != 0) {
        warn("nng_pair0_open FAIL {}\n", nng_ret);
    }
    listen(client.srv, myUrl);

    const socket2 = allocator.create(sock) catch unreachable;
    client.clnt = socket2;
    nng_ret = c.nng_pair0_open(client.clnt);
    if (nng_ret != 0) {
        warn("nng_pair0_open FAIL {}\n", nng_ret);
    }
    dial(client.clnt, myUrl);
    return client;
}

pub fn send(client: *Client) void {
    var payload = "X";
    warn("nng send {} {}\n", client, payload);
    if (c.nng_send(client.clnt.*, util.sliceToCstr(std_allocator, payload), payload.len, 0) != 0) {
        warn("nng send to master FAIL\n");
    }
}
