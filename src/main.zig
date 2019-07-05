// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const allocator = std.heap.c_allocator;

const simple_buffer = @import("./simple_buffer.zig");
const auth = @import("./auth.zig");
const gui = @import("./gui.zig");
const net = @import("./net.zig");
const heartbeat = @import("./heartbeat.zig");
const config = @import("./config.zig");
const state = @import("./statemachine.zig");
const thread = @import("./thread.zig");
const db = @import("./db/lmdb.zig");
const dbfile = @import("./db/file.zig");
const statemachine = @import("./statemachine.zig");
const util = @import("./util.zig");
const toot_list = @import("./toot_list.zig");
const toot_lib = @import("./toot.zig");
const json_lib = @import("./json.zig");
const html_lib = @import("./html.zig");

var settings: config.Settings = undefined;

pub fn main() !void {
  hello();
  try initialize();

  if (config.readfile("config.json")) |config_data| {
    settings = config_data;
    var guiThread = thread.create(gui.go, undefined, guiback);
    var heartbeatThread = thread.create(heartbeat.go, undefined, heartback);

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
  try heartbeat.init(allocator);
  try statemachine.init(allocator);
  try db.init(allocator);
  try dbfile.init(allocator);
  try thread.init(allocator);
  try gui.init(allocator, &settings);
}

fn statewalk() void {
  if(statemachine.state == statemachine.States.Init) {
    statemachine.setState(statemachine.States.Setup); // transition
    gui.schedule(gui.show_main_schedule, @ptrCast(*c_void, &[_]u8{1}));
    for(settings.columns.toSlice()) |column| {
      if(column.config.token) |token| {
        profileget(column);
      }
    }
    for(settings.columns.toSlice()) |column| {
      gui.schedule(gui.add_column_schedule, column);
    }
  }

  if(statemachine.state == statemachine.States.Setup) {
    statemachine.setState(statemachine.States.Running); // transition
    columns_net_freshen();
  }
}

fn hello() void {
  warn("zootdeck {} {} tid {x}\n", @tagName(builtin.os), @tagName(builtin.arch), thread.self());
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
  var netthread = thread.create(net.go, verb, netback) catch unreachable;
}

fn profileget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  httpInfo.url = std.fmt.allocPrint(allocator, "https://{}/api/v1/accounts/verify_credentials", column.config.url) catch unreachable;
  httpInfo.verb = .get;
  httpInfo.token = null;
  if(column.config.token) |tokenStr| {
    httpInfo.token = tokenStr;
  }
  httpInfo.column = column;
  httpInfo.response_code = 0;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(net.go, verb, profileback) catch unreachable;
}

fn photoget(toot: toot_lib.TootType, url: []const u8) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  httpInfo.url = url;
  httpInfo.verb = .get;
  httpInfo.token = null;
  httpInfo.response_code = 0;
  httpInfo.toot = toot;
  verb.http = httpInfo;
  var netthread = thread.create(net.go, verb, photoback) catch unreachable;
}

fn oauthcolumnget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  auth.oauthClientRegister(allocator, httpInfo, column.config.url);
  httpInfo.token = null;
  httpInfo.column = column;
  httpInfo.response_code = 0;
  httpInfo.verb = .post;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(net.go, verb, oauthback) catch unreachable;
//  defer thread.destroy(allocator, netthread);
}

fn oauthtokenget(column: *config.ColumnInfo, code: []const u8) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  auth.oauthTokenUpgrade(allocator, httpInfo, column.config.url, code,
                         column.oauthClientId.?, column.oauthClientSecret.?);
  httpInfo.token = null;
  httpInfo.column = column;
  httpInfo.response_code = 0;
  httpInfo.verb = .post;
  verb.http = httpInfo;
  gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(*c_void, httpInfo));
  var netthread = thread.create(net.go, verb, oauthtokenback) catch unreachable;
}

fn oauthtokenback(command: *thread.Command) void {
  warn("*oauthtokenback tid {x} {}\n", thread.self(), command);
  const column = command.verb.http.column;
  const http = command.verb.http;
  if (http.response_code >= 200 and http.response_code < 300) {
    const tree = command.verb.http.tree;
    var rootJsonType = @TagType(std.json.Value)(tree.root);
    if (rootJsonType == .Object) {
      if(tree.root.Object.get("access_token")) |cid| {
        column.config.token = cid.value.String;
        config.writefile(settings, "config.json");
        column.config.last_check = 0;
        gui.schedule(gui.update_column_config_oauth_finalize_schedule, @ptrCast(*c_void, column));
      }
    } else {
      warn("*oauthtokenback json err body {}\n", http.body);
    }
  } else {
    warn("*oauthtokenback net err {}\n", http.response_code);
  }
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
            if(column.toots.contains(item)) {
              // dupe
            } else {
              column.toots.sortedInsert(item, allocator);
              var html = item.get("content").?.value.String;
              var root = html_lib.parse(html);
              html_lib.search(root);
              cache_update(item);
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
    gui.schedule(gui.update_column_toots_schedule, @ptrCast(*c_void, column));
  }
}

fn photoback(command: *thread.Command) void {
  const reqres = command.verb.http;
  var account = reqres.toot.get("account").?.value.Object;
  const acct = account.get("acct").?.value.String;
  warn("photoback! acct {} type {} size {}\n", acct, reqres.content_type, reqres.body.len);
  dbfile.write(acct, "photo", reqres.body, allocator) catch unreachable;
}

fn profileback(command: *thread.Command) void {
  const reqres = command.verb.http;
  warn("*!*! PROFILE profileback! {} \n", reqres.body);
  reqres.column.account = command.verb.http.tree.root.Object;
  gui.schedule(gui.update_column_ui_schedule, @ptrCast(*c_void, reqres.column));
}

fn cache_update(toot: toot_lib.TootType) void {
  var account = toot.get("account").?.value.Object;
  const acct: []const u8 = account.get("acct").?.value.String;
  const avatar_url: []const u8 = account.get("avatar").?.value.String;
  db.write(acct, "photo_url", avatar_url, allocator) catch unreachable;
  const name: []const u8 = account.get("display_name").?.value.String;
  db.write(acct, "name", name, allocator) catch unreachable;
  if(dbfile.has(acct, "photo", allocator)) {
  } else {
    photoget(toot, avatar_url);
  }
}

fn guiback(command: *thread.Command) void {
  warn("*guiback tid {x} {*}\n", thread.self(), command);
  if (command.id == 1) {
    gui.schedule(gui.show_main_schedule, @ptrCast(*c_void, &[_]u8{1}));
  }
  if (command.id == 2) { // refresh button
    const column = command.verb.column;
    column.refreshing = false;
    column.config.last_check = 0;
  }
  if (command.id == 3) { // add column
    var colInfo = allocator.create(config.ColumnInfo) catch unreachable;
    colInfo.reset();
    colInfo.toots = toot_list.TootList.init();
    settings.columns.append(colInfo) catch unreachable;
    var colConfig = allocator.create(config.ColumnConfig) catch unreachable;
    colInfo.config = colConfig;
    colInfo.config.title = ""[0..];
    colInfo.config.url = "mastodon.example.com"[0..];
    colInfo.config.last_check = 0;
    gui.schedule(gui.add_column_schedule, @ptrCast(*c_void, colInfo));
    warn("Settings PreWrite Columns count {}\n", settings.columns.len);
    config.writefile(settings, "config.json");
  }
  if (command.id == 4) { // config done
    warn("gui col config {}\n", command.verb.column.config.title);
    const column = command.verb.column;
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
    const myAuth = command.verb.auth.*;
    warn("oauth authorization {}\n", myAuth.code);
    oauthtokenget(myAuth.column, myAuth.code);
  }
  if (command.id == 8) { //column host change
    const column = command.verb.column;
    // partial reset
    column.oauthClientId = null;
    column.oauthClientSecret = null;
    gui.schedule(gui.update_column_ui_schedule, @ptrCast(*c_void, column));
    // throw out toots in the toot list not from the new host

  }
}

fn heartback(nuthin: *thread.Command) void {
  warn("*heartback tid {x} {}\n", thread.self(), nuthin);
  columns_net_freshen();
}

fn columns_net_freshen() void {
  for(settings.columns.toSlice()) |column, idx| {
    var now = config.now();
    const refresh = 60;
    const since = now - column.config.last_check;
    if(since > refresh) {
      column_refresh(column);
    } else {
      warn("col {} is fresh for {} sec\n", column.makeTitle(), refresh-since);
    }
  }
}

fn column_refresh(column: *config.ColumnInfo) void {
  if(column.refreshing) {
    warn("column {} in {}\n", column.makeTitle(), if (column.inError) "error!" else "progress");
  } else {
    warn("column http get {}\n", column.makeTitle());
    column.refreshing = true;
    columnget(column);
  }
}
