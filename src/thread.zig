// thread.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;
var allocator: *Allocator = undefined;
const ipc = @import("./ipc-epoll.zig");
const config = @import("./config.zig");

const c = @cImport({
  @cInclude("unistd.h");
  @cInclude("pthread.h");
  @cInclude("sys/epoll.h");
});

pub const Actor = struct {
  thread_id: c.pthread_t,
  client: *ipc.Client,
  payload: *CommandVerb,
  recvback: fn(*Command) void
};

pub const Command = packed struct {
  id: u16,
  verb: *CommandVerb
};

pub const CommandVerb = packed union {
  login: *config.LoginInfo,
  http: *config.HttpInfo,
  column: *config.ColumnInfo,
  auth: *config.ColumnAuth,
  idle: u16
};

var actors: std.ArrayList(Actor) = undefined;

pub fn init(myAllocator: *Allocator) !void {
  allocator = myAllocator;
  actors = std.ArrayList(Actor).init(allocator);
  try ipc.init();
}

pub fn create(
              startFn: extern fn (?*c_void) ?*c_void,
              startParams: *CommandVerb,
              recvback: fn(*Command) void,
              ) !*Actor {
  var actor = try allocator.create(Actor);
  actor.client = ipc.newClient(allocator);
  actor.payload = startParams; //unused
  ipc.dial(actor.client, "");
  actor.recvback = recvback;
  //ipc.register(actor.client, recvback);
  const null_pattr = @intToPtr([*c]const c.union_pthread_attr_t, 0);
  var terr = c.pthread_create(&actor.thread_id, null_pattr, startFn, actor);
  if (terr == 0) {
      warn("created thread#{}\n", actor.thread_id);
      var err = actors.append(actor.*);
      return actor;
  } else {
      warn("ERROR thread {} {}\n", terr, actor);
  }
  return error.BadValue;
}

pub fn destroy(actor: *Actor) void {
  warn("thread.destroy {}\n", actor);
}

pub fn self() c.pthread_t {
  return c.pthread_self();
}

pub fn wait() void {
  var client_aaaa = ipc.wait();
  var cp_int: usize = @ptrToInt(client_aaaa); // possible zig 0.4 bug
  var cptr_zigbug = cp_int & 0x00000000ffffffff; // override unallocated ram marker of 0xaaaaaaaa
  var client = @intToPtr(*ipc.Client, cptr_zigbug);

  var bufArray = []u8{0} ** 16; // arbitrary receive buffer
  const buf: []u8 = ipc.read(client, bufArray[0..]);
  if(buf.len == 0) {
    // todo: skip read() and pass ptr with event_data
    warn("thread.wait ipc.read no socket payload! DEFLECTED!\n");
  } else {
    const b8: *[@sizeOf(usize)]u8 = @ptrCast(*[@sizeOf(usize)]u8, buf.ptr);
    var command: *Command = std.mem.bytesAsValue(*Command, b8).*;
    for(actors.toSlice()) |actor| { // todo: hashtable
      if(actor.client == client) {
        actor.recvback(command);
        break;
      }
    }
  }
}

pub fn signal(actor: *Actor, command: *Command) void {
  const command_addr_bytes = @ptrCast(*const [@sizeOf(*Command)]u8, &command) ;
  warn("signaling from tid {x} command bytes {x8} len{} {}\n", actor.thread_id, command_addr_bytes, command_addr_bytes.len, command);
  ipc.send(actor.client, command_addr_bytes);
}

pub fn join(jthread: c.pthread_t, joinret: *?*c_void) c_int {
  //pub extern fn pthread_join(__th: pthread_t, __thread_return: ?[*](?*c_void)) c_int;
  return c.pthread_join(jthread, @ptrCast(?[*]?*c_void, joinret)); //expected type '?[*]?*c_void' / void **value_ptr
}

