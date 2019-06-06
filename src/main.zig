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
const simple_buffer = @import("./simple_buffer.zig");

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
  //try db.init(allocator);
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

fn columnget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  httpInfo.url = util.mastodonExpandUrl(column.config.url, if(column.config.token) |tk| true else false, allocator);
  httpInfo.verb = .get;
  httpInfo.token = null;
  if(column.config.token) |tokenStr| {
    httpInfo.token = tokenStr;
  }
  httpInfo.column = column;
  httpInfo.response_code = 0;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(allocator, net.go, verb, netback) catch unreachable;
//  defer thread.destroy(allocator, netthread);
}

fn oauthcolumnget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;

  var urlBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  urlBuf.append("https://") catch unreachable;
  urlBuf.append(column.config.url) catch unreachable;
  urlBuf.append("/api/v1/apps") catch unreachable;
  httpInfo.url = urlBuf.toSliceConst();
  var postBodyBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  postBodyBuf.append("client_name=zootdeck") catch unreachable;
  postBodyBuf.append("&scopes=read+write") catch unreachable;
  postBodyBuf.append("&redirect_uris=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
  httpInfo.post_body = postBodyBuf.toSliceConst();
  httpInfo.token = null;
  httpInfo.column = column;
  httpInfo.response_code = 0;
  httpInfo.verb = .post;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(allocator, net.go, verb, oauthback) catch unreachable;
//  defer thread.destroy(allocator, netthread);
}

fn oauthtokenget(column: *config.ColumnInfo, code: []const u8) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  var urlBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  urlBuf.append("https://") catch unreachable;
  urlBuf.append(column.config.url) catch unreachable;
  urlBuf.append("/oauth/token") catch unreachable;
  httpInfo.url = urlBuf.toSliceConst();
  var postBodyBuf = simple_buffer.SimpleU8.initSize(allocator, 0) catch unreachable;
  postBodyBuf.append("client_id=") catch unreachable;
  postBodyBuf.append(column.oauthClientId.?) catch unreachable;
  postBodyBuf.append("&client_secret=") catch unreachable;
  postBodyBuf.append(column.oauthClientSecret.?) catch unreachable;
  postBodyBuf.append("&grant_type=authorization_code") catch unreachable;
  postBodyBuf.append("&code=") catch unreachable;
  postBodyBuf.append(code) catch unreachable;
  postBodyBuf.append("&redirect_uri=urn:ietf:wg:oauth:2.0:oob") catch unreachable;
  httpInfo.post_body = postBodyBuf.toSliceConst();
  httpInfo.token = null;
  httpInfo.column = column;
  httpInfo.response_code = 0;
  httpInfo.verb = .post;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(allocator, net.go, verb, oauthtokenback) catch unreachable;
}

fn oauthtokenback(command: *thread.Command) void {
  warn("*oauthtokenback tid {x} {}\n", thread.self(), command);
  const column = command.verb.http.column;
  const http = command.verb.http;
}

fn oauthback(command: *thread.Command) void {
  warn("*oauthback tid {x} {}\n", thread.self(), command);
  const column = command.verb.http.column;
  const http = command.verb.http;
  if (http.response_code >= 200 and http.response_code < 300) {
    const tree = command.verb.http.tree;
    var rootJsonType = @TagType(std.json.Value)(tree.root);
    if (rootJsonType == .Object) {
      if(tree.root.Object.get("client_id")) |cid| {
        column.oauthClientId = cid.value.String;
      }
      if(tree.root.Object.get("client_secret")) |cid| {
        column.oauthClientSecret = cid.value.String;
      }
      warn("*oauthback client id {} secret {}\n", column.oauthClientId, column.oauthClientSecret);
      gui.schedule(gui.column_config_oauth_url_schedule, @ptrCast(*c_void, column));
    } else {
      warn("*oauthback json err body {}\n", http.body);
    }
  } else {
    warn("*oauthback net err {}\n", http.response_code);
  }
}

fn netback(command: *thread.Command) void {
  warn("*netback tid {x} {}\n", thread.self(), command);
  if (command.id == 1) {
    gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, command.verb.http));
    var column = command.verb.http.column;
    column.refreshing = false;
    column.config.last_check = config.now();
    if(command.verb.http.response_code >= 200 and command.verb.http.response_code < 300) {
      if(command.verb.http.body.len > 0) {
        const tree = command.verb.http.tree;
        var rootJsonType = @TagType(std.json.Value)(tree.root);
        if(rootJsonType == .Array) {
          column.inError = false;
          for(tree.root.Array.toSlice()) |jsonValue| {
            const item = jsonValue.Object;
            var id = item.get("id").?.value.String;
            if(util.listContains(config.TootType, column.toots, item)) {
              //warn("sorted list dupe! {} \n", id);
            } else {
              util.listSortedInsert(config.TootType, &column.toots, item, allocator);
            }
          }
        } else if(rootJsonType == .Object) {
          if(tree.root.Object.get("error")) |err| {
            warn("netback json err {} \n", err.value.String);
          }
        }
      } else { // empty body
        column.inError = true;
      }
    } else {
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
  if (command.id == 3) { // add column
    var colInfo = allocator.create(config.ColumnInfo) catch unreachable;
    colInfo.reset();
    colInfo.toots = config.TootList.init();
    settings.columns.append(colInfo) catch unreachable;
    var colConfig = allocator.create(config.ColumnConfig) catch unreachable;
    colInfo.config = colConfig;
    var titleBuf = allocator.alloc(u8,256) catch unreachable;
    var title = std.fmt.bufPrint(titleBuf, "{}{}", "Column #", settings.columns.count()) catch unreachable;
    colInfo.config.title = title;
    colInfo.config.url = "https://mastodon.example"[0..];
    colInfo.config.last_check = 0;
    gui.schedule(gui.add_column_schedule, @ptrCast(*c_void, colInfo));
    warn("Settings PreWrite Columns count {}\n", settings.columns.len);
    config.writefile(settings, "config.json");
  }
  if (command.id == 4) { // config done
    warn("gui col config {}\n", command.verb.guiColumnConfig.config.title);
    const column = command.verb.guiColumnConfig;
    column.inError = false;
    column.config.last_check = 0;
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
  if (command.id == 6) { //oauth
    const column = command.verb.column;
    if (column.oauthClientId) |clientId| {
      gui.schedule(gui.column_config_oauth_url_schedule, @ptrCast(*c_void, column));
    } else {
      oauthcolumnget(column);
    }
  }
  if (command.id == 7) { //oauth activate
    const auth = command.verb.auth.*;
    warn("oauth authorization {}\n", auth.code);
    oauthtokenget(auth.column, auth.code);
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
    warn("column {} in {}\n", column.config.title, if (column.inError) "error!" else "progress");
  } else {
    warn("column {} get {}\n", column.config.title, column.config.url);
    column.refreshing = true;
    columnget(column);
  }
}
