const std = @import("std");
const warn = std.debug.warn;
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
    if(epoll_instance == -1) {
      return error.BadValue;
    }
}

pub fn newClient(allocator: *Allocator) *Client {
  const client = allocator.create(Client) catch unreachable;
  const fds = allocator.alloc(SocketType, 2) catch unreachable;
  _ = c.pipe(fds.ptr);
  client.readSocket = fds[0];
  client.writeSocket = fds[1];
  allocator.free(fds);
  client.readEvent = allocator.create(c.epoll_event) catch unreachable;
  return client;
}

pub fn listen(socket: *sockSingle, url: []u8) void {
  warn("epoll_listen\n");
}

pub fn register(client: *Client, callback: extern fn(?*c_void) void) void {
}

pub fn dial(client: *Client, url: []u8) void {
  //.events = u32(c_int(c.EPOLL_EVENTS.EPOLLIN))|u32(c_int(c.EPOLL_EVENTS.EPOLLET)),
  // IN=1, OUT=4, ET=-1
  client.readEvent.events =  0x001;
  client.readEvent.data.ptr = client;
  _ = c.epoll_ctl(epoll_instance, c.EPOLL_CTL_ADD, client.readSocket, client.readEvent);
}

pub fn wait() *Client {
  const max_fds = 1;
  var events_waiting: [max_fds]c.epoll_event = undefined; //[]c.epoll_event{.data = 1};
  var nfds = c_int(-1);
  while (nfds < 0) {
    nfds = c.epoll_wait(epoll_instance, @ptrCast([*c]c.epoll_event, &events_waiting), max_fds, -1);
    if (nfds < 0) {
      const errnoPtr: [*c]c_int = c.__errno_location();
      const errno = errnoPtr.*;
      warn("epoll_wait ignoring errno {}\n", errno);
    }
  }
  var dsizeof: usize = @sizeOf(@typeOf(events_waiting[0].data));
  var psizeof: usize = @sizeOf(@typeOf(events_waiting[0].data.ptr));
  warn("epoll {} waiting. events[0] {b} waiting {} align{} waiting.data {} align{}\n",
             nfds,
             events_waiting[0].events,
             events_waiting[0].data,
             dsizeof,
             events_waiting[0].data.ptr,
             psizeof);
  var clientdata = @alignCast(@alignOf(Client), events_waiting[0].data.ptr);
  var client = @ptrCast(*Client, clientdata);
  return client;
}

pub fn read(client: *Client, buf: []u8) []u8 {
  var readCountOrErr = c.read(client.readSocket, buf.ptr, 1);
  if (readCountOrErr >= 0) {
    var readcount: usize = @intCast(usize, readCountOrErr); //@ptrCast(*usize, &readCountOrErr).*;
    if (readcount+1 < buf[0]) {
      var r2ce = c.read(client.readSocket, buf.ptr+readcount, buf.len-readcount);
      if (r2ce >= 0) {
        var r2c: usize = @intCast(usize, r2ce);
      } else {
        warn("read2 ERR\n");
      }
    }
    return buf[1..buf[0]+1];
  } else {
    warn("read ERR\n");
    return buf;
  }
}

pub fn send(client: *Client, buf:[]const u8) void {
  var len8: u8 = @intCast(u8, buf.len);
  var writecount = c.write(client.writeSocket, &len8, 1); // send the size
  writecount = writecount + c.write(client.writeSocket, buf.ptr, buf.len);
}
