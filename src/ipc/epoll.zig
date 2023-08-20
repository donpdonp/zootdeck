const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("sys/epoll.h");
});

pub const SocketType = c_int;
pub const Client = packed struct {
    readEvent: *c.epoll_event,
    readSocket: SocketType,
    writeSocket: SocketType,
};

var epoll_instance: c_int = undefined;

pub fn init() !void {
    epoll_instance = c.epoll_create(256);
    if (epoll_instance == -1) {
        return error.BadValue;
    }
}

pub fn newClient(allocator: Allocator) *Client {
    const client = allocator.create(Client) catch unreachable;
    const fds = allocator.alloc(SocketType, 2) catch unreachable;
    _ = c.pipe(fds.ptr);
    client.readSocket = fds[0];
    client.writeSocket = fds[1];
    allocator.free(fds);
    client.readEvent = allocator.create(c.epoll_event) catch unreachable;
    return client;
}

pub fn close(client: *Client) void {
    _ = c.close(client.readSocket);
    _ = c.close(client.writeSocket);
}

//pub fn listen(socket: u8, url: []u8) void {
//    _ = socket;
//    warn("epoll_listen\n", .{});
//}

pub fn register(client: *Client, callback: fn (?*anyopaque) callconv(.C) void) void {
    _ = callback;
    _ = client;
}

pub fn dial(client: *Client, url: []u8) void {
    _ = url;
    //.events = u32(c_int(c.EPOLL_EVENTS.EPOLLIN))|u32(c_int(c.EPOLL_EVENTS.EPOLLET)),
    // IN=1, OUT=4, ET=-1
    client.readEvent.events = 0x001;
    client.readEvent.data.ptr = client;
    _ = c.epoll_ctl(epoll_instance, c.EPOLL_CTL_ADD, client.readSocket, client.readEvent);
}

pub fn wait() *Client {
    const max_fds = 1;
    var events_waiting: [max_fds]c.epoll_event = undefined; //[]c.epoll_event{.data = 1};
    var nfds: c_int = -1;
    while (nfds < 0) {
        nfds = c.epoll_wait(epoll_instance, @as([*c]c.epoll_event, @ptrCast(&events_waiting)), max_fds, -1);
        if (nfds < 0) {
            const errnoPtr: [*c]c_int = c.__errno_location();
            const errno = errnoPtr.*;
            warn("epoll_wait ignoring errno {}\n", .{errno});
        }
    }
    var client = @as(*Client, @ptrCast(@alignCast(events_waiting[0].data.ptr)));
    return client;
}

pub fn read(client: *Client, buf: []u8) []u8 {
    const pkt_fixed_portion = 1;
    var readCountOrErr = c.read(client.readSocket, buf.ptr, pkt_fixed_portion);
    if (readCountOrErr >= pkt_fixed_portion) {
        const msglen: usize = buf[0];
        var msgrecv = @as(usize, @intCast(readCountOrErr - pkt_fixed_portion));
        if (msgrecv < msglen) {
            var msgleft = msglen - msgrecv;
            var r2ce = c.read(client.readSocket, buf.ptr, msgleft);
            if (r2ce >= 0) {
                msgrecv += @as(usize, @intCast(r2ce));
            } else {
                warn("epoll read #2 ERR\n", .{});
            }
        }
        if (msgrecv == msglen) {
            return buf[0..msgrecv];
        } else {
            return buf[0..0];
        }
    } else {
        warn("epoll client read starved. tried {} got {} bytes\n", .{ pkt_fixed_portion, readCountOrErr });
        return buf[0..0];
    }
}

pub fn send(client: *Client, buf: []const u8) void {
    var len8: u8 = @as(u8, @intCast(buf.len));
    var writecount = c.write(client.writeSocket, &len8, 1); // send the fixed-size portion
    writecount = writecount + c.write(client.writeSocket, buf.ptr, buf.len);
}
