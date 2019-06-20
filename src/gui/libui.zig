// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;

const thread = @import("../thread.zig");

const c = @cImport({
  @cInclude("stdio.h");
  @cInclude("ui.h");
});

const GUIError = error{Init, Setup};

pub const Column = struct {
//  builder: [*c]c.GtkBuilder,
//  columnbox: [*c]c.GtkWidget,
//  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo
};

var myActor: *thread.Actor = undefined;

pub fn libname() []const u8 {
  return "libui";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  var tf = usize(1);
  if(tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
  myActor = actor;
  var uiInitOptions = c.uiInitOptions{ .Size = 0 };
  var err = c.uiInit(&uiInitOptions);

  if (err == 0) {
    build();
  } else {
    warn("libui init failed {}\n", err);
    return GUIError.Init;
  }
}

fn build() void {
  var window = c.uiNewWindow(c"Tootdeck", 320, 240, 0);
  c.uiWindowSetMargined(window, 1);
  const f: ?extern fn (*c.uiWindow, *c_void) c_int = onClosing;
  c.uiWindowOnClosing(window, f, null);

  var hbox = c.uiNewHorizontalBox();
  c.uiWindowSetChild(window, @ptrCast(*c.uiControl, @alignCast(8, hbox)));

  var label = c.uiNewLabel(c"z1");
  c.uiLabelSetText(label, c"zoooot");
  c.uiBoxAppend(hbox, @ptrCast(*c.uiControl, @alignCast(8, label)), 0);
  var control = @ptrCast(*c.uiControl, @alignCast(8, window));
  c.uiControlShow(control);
}

pub fn mainloop() void {
  c.uiMain();
}

pub fn gui_end() void {
}

export fn onClosing(w: *c.uiWindow, data: *c_void) c_int {
  warn("ui quitting\n");
  c.uiQuit();
  return 1;
}

pub fn schedule(func: ?extern fn(*c_void) c_int, param: *c_void) void {
}

pub extern fn show_main_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn add_column_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn column_remove_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn column_config_oauth_url_schedule(in: *c_void) c_int {
  return 0;
}


pub extern fn update_column_config_oauth_finalize_schedule(in: *c_void) c_int {
  return 0;
}


pub extern fn update_column_ui_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn update_column_netstatus_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn update_column_toots_schedule(in: *c_void) c_int {
  return 0;
}

