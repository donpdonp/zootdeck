// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const allocator = std.heap.c_allocator;

const gui = @import("./gui-gtk.zig");
const net = @import("./net.zig");
const heartbeat = @import("./heartbeat.zig");
const config = @import("./config.zig");
const state = @import("./statemachine.zig");
const thread = @import("./thread.zig");
const db = @import("./db.zig");
const statemachine = @import("./statemachine.zig");
const util = @import("./util.zig");

var settings: config.Settings = undefined;

const c = @cImport({
  @cInclude("time.h");
});

pub fn main() !void {
  hello();
  try initialize();

  if (config.readfile("config.json")) |config_data| {
    settings = config_data;
    warn("settings colcount {}\n", settings.columns.count());
    var guiThread = thread.create(allocator, gui.go, undefined, guiback) catch unreachable;
    var heartbeatThread = thread.create(allocator, heartbeat.go, undefined, heartback) catch unreachable;

    while(true) {
      statewalk();
      warn("== main wait ==\n");
      thread.wait(); // main ipc listener
    }
  } else |err| {
    warn("config error {}\n", err);
  }
}

fn initialize() !void {
  try config.init(allocator);
  try statemachine.init(allocator);
  try db.init(allocator);
  try thread.init(allocator);
  try gui.init(allocator, &settings);
}

fn statewalk() void {
  if(statemachine.state == statemachine.States.Init) {
    gui.schedule(gui.show_main_schedule, @ptrCast(*c_void, &[]u8{1}));
    for(settings.columns.toSlice()) |column| {
      gui.schedule(gui.add_column_schedule, column);
    }
    statemachine.setState(statemachine.States.Setup);
  }

  if(statemachine.state == statemachine.States.Setup) {
    warn("the setup stuff\n");
    statemachine.setState(statemachine.States.Running);
  }
}

fn hello() void {
  warn("tootdeck {} {} tid {x}\n", @tagName(builtin.os), @tagName(builtin.arch), thread.self());
}

fn urlget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  httpInfo.url = column.config.url;
  httpInfo.token = null;
  if(column.config.token) |token| {
    httpInfo.token = token;
  }
  httpInfo.column = column;
  httpInfo.response_code = 0;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(allocator, net.go, verb.*, netback) catch unreachable;
//  defer thread.destroy(allocator, netthread);
}

fn netback(command: *thread.Command) void {
  warn("*netback tid {x} {}\n", thread.self(), command);
  if (command.id == 1) {
    gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, command.verb.http));
    var column = command.verb.http.column;
    if(command.verb.http.response_code == 200) {
      const tree = command.verb.http.tree;
      var rootJsonType = @TagType(std.json.Value)(tree.root);
      if(rootJsonType == .Array) {
        column.inError = false;
        for(tree.root.Array.toSlice()) |jsonValue| {
          const item = jsonValue.Object;
          var id = item.get("id").?.value.String;
          if(util.listContains(config.TootType, column.toots.*, item)) {
            //warn("sorted list dupe! {} \n", id);
          } else {
            util.listSortedInsert(config.TootType, column.toots, item, allocator);
          }
        }
      } else if(rootJsonType == .Object) {
        if(tree.root.Object.get("error")) |err| {
          warn("netback json err {} \n", err.value.String);
        }
      }
      column.refreshing = false;
      column.config.last_check = config.now();
    } else {
      warn("COLUMN NET HTTP FAIL {}\n", command.verb.http.response_code);
      column.inError = true;
    }
    gui.schedule(gui.update_column_schedule, @ptrCast(*c_void, column));
  }
}

fn guiback(command: *thread.Command) void {
  warn("*guiback tid {x} {}\n", thread.self(), command);
  if (command.id == 1) {
    gui.schedule(gui.show_main_schedule, @ptrCast(*c_void, &[]u8{1}));
  }
  if (command.id == 2) { // refresh button
    const column = command.verb.column;
    column.refreshing = false;
    column.config.last_check = 0;
  }
  if (command.id == 3) {
    var colInfo = allocator.create(config.ColumnInfo) catch unreachable;
    colInfo.reset();
    settings.columns.append(colInfo) catch unreachable;
    var colConfig = allocator.create(config.ColumnConfig) catch unreachable;
    colInfo.config = colConfig;
    var titleBuf = allocator.alloc(u8,256) catch unreachable;
    var title = std.fmt.bufPrint(titleBuf, "{}{}", "maintitle", settings.columns.count()) catch unreachable;
    colInfo.config.title = title;
    colInfo.config.url = "url"[0..];
    colInfo.config.last_check = 0;
    gui.schedule(gui.add_column_schedule, @ptrCast(*c_void, colInfo));
    warn("Settings PreWrite Columns count {}\n", settings.columns.len);
    config.writefile(settings, "config.json");
  }
  if (command.id == 4) {
    warn("gui col config {}\n", command.verb.guiColumnConfig.config.title);
    config.writefile(settings, "config.json");
  }
  if (command.id == 5) {
    const column = command.verb.column;
    warn("gui col remove {}\n", column.config.title);
    var colpos: usize = undefined;
    for (settings.columns.toSlice()) |col, idx| {
      if(col == column) {
        _ = settings.columns.orderedRemove(idx);
        break;
      }
    }
    config.writefile(settings, "config.json");
    gui.schedule(gui.column_remove_schedule, @ptrCast(*c_void, column));
  }
}

fn heartback(nuthin: *thread.Command) void {
  warn("*heartback tid {x} {}\n", thread.self(), nuthin);

  for(settings.columns.toSlice()) |column, idx| {
    var now = config.now();
    const refresh = 60;
    const since = now - column.config.last_check;
    if(since > refresh) {
      column_refresh(column);
    } else {
      warn("col {} is fresh for {} sec\n", column.config.title, refresh-since);
    }
  }
}

fn column_refresh(column: *config.ColumnInfo) void {
  if(column.refreshing) {
    warn("column {} in {}.\n", column.config.title, if (column.inError) "error!" else "progress");
  } else {
    warn("column {} get {}\n", column.config.title, column.config.url);
    column.refreshing = true;
    urlget(column);
  }
}
