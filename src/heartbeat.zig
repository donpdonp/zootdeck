const std = @import("std");
const warn = std.debug.warn;
const thread = @import("./thread.zig");

const c = @cImport({
  @cInclude("unistd.h");
});

pub extern fn go(data: ?*c_void) ?*c_void {
  var data8 = @alignCast(@alignOf(thread.Actor), data);
  var actor = @ptrCast(*thread.Actor, data8);
  warn("heartbeat thread start {*} {}\n", actor, actor);
  while (true) {
    _ = c.usleep(3 * 1000000);
    thread.signal(actor, &thread.Command{.id = 3, .verb = undefined});
  }
  return null;
}
