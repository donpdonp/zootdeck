// gui.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const config = @import("./config.zig");
const toot_lib = @import("./toot.zig");
const thread = @import("./thread.zig");

const gtk = @import("./gui/gtk.zig");
const qt = @import("./gui/qt.zig");

const guilib = gtk;

const GUIError = error{Init};
const Column = gtk.Column;
var columns:std.ArrayList(*Column) = undefined;
var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  settings = set;
  allocator = alloca;
  columns = std.ArrayList(*Column).init(allocator);
  try gtk.init(alloca, set);
}

var myActor: *thread.Actor = undefined;
var stop = false;

pub extern fn go(data: ?*c_void) ?*c_void {
  var data8 = @alignCast(@alignOf(thread.Actor), data);
  myActor = @ptrCast(*thread.Actor, data8);
  warn("gui-gtk thread start {*} {}\n", myActor, myActor);
  if (guilib.gui_setup()) {
    // mainloop
    while (!stop) {
        guilib.mainloop();
    }
    guilib.gui_end();
  } else |err| {
      warn("gui error {}\n", err);
  }
  return null;
}

pub fn schedule(func: ?extern fn(*c_void) c_int, param: *c_void) void {
  guilib.schedule(func, param);
}

pub extern fn show_main_schedule(in: *c_void) c_int {
  return guilib.show_main_schedule(in);
}

pub extern fn add_column_schedule(in: *c_void) c_int {
  return guilib.add_column_schedule(in);
}

pub extern fn column_remove_schedule(in: *c_void) c_int {
  return guilib.column_remove_schedule(in);
}

pub extern fn column_config_oauth_url_schedule(in: *c_void) c_int {
  return guilib.column_config_oauth_url_schedule(in);
}

pub extern fn update_column_config_oauth_finalize_schedule(in: *c_void) c_int {
  return guilib.update_column_config_oauth_finalize_schedule(in);
}

pub extern fn update_column_ui_schedule(in: *c_void) c_int {
  return guilib.update_column_ui_schedule(in);
}

pub extern fn update_column_netstatus_schedule(in: *c_void) c_int {
  return guilib.update_column_netstatus_schedule(in);
}

pub extern fn update_column_toots_schedule(in: *c_void) c_int {
  return guilib.update_column_toots_schedule(in);
}



