// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const callocator = std.heap.c_allocator;
const logAlloc = @import("warning_allocator.zig").WarningAllocator;
//const allocator = &logAlloc.init(callocator).allocator;
const allocator = callocator;

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
const filter_lib = @import("./filter.zig");

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
      warn("== epoll wait\n");
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
  httpInfo.url = util.mastodonExpandUrl(column.filter.host(),
                  if(column.config.token) |tk| true else false, allocator);
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
  httpInfo.url = std.fmt.allocPrint(allocator, "https://{}/api/v1/accounts/verify_credentials",
                                 column.filter.host()) catch unreachable;
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

fn photoget(toot: *toot_lib.Type, url: []const u8) void {
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

fn mediaget(toot: *toot_lib.Type, url: []const u8) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  httpInfo.url = url;
  httpInfo.verb = .get;
  httpInfo.token = null;
  httpInfo.response_code = 0;
  httpInfo.toot = toot;
  verb.http = httpInfo;
  warn("mediaget toot {} {*}\n", toot.id(), &toot);
  var netthread = thread.create(net.go, verb, mediaback) catch unreachable;
}

fn oauthcolumnget(column: *config.ColumnInfo) void {
  var verb = allocator.create(thread.CommandVerb) catch unreachable;
  var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
  auth.oauthClientRegister(allocator, httpInfo, column.filter.host());
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
  auth.oauthTokenUpgrade(allocator, httpInfo, column.filter.host(), code,
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
        column.last_check = 0;
        profileget(column);
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
    column.last_check = config.now();
    if(command.verb.http.response_code >= 200 and command.verb.http.response_code < 300) {
      if(command.verb.http.body.len > 0) {
        const tree = command.verb.http.tree;
        var rootJsonType = @TagType(std.json.Value)(tree.root);
        if(rootJsonType == .Array) {
          column.inError = false;
          for(tree.root.Array.toSlice()) |jsonValue| {
            const item = jsonValue.Object;
            var toot = allocator.create(toot_lib.Type) catch unreachable;
            toot.init(item, allocator);
            var id = toot.id();
            warn("netback json create toot #{} {*}\n", toot.id(), toot);
            if(column.toots.contains(toot)) {
              // dupe
            } else {
              var images = toot.get("media_attachments").?.value.Array;
              column.toots.sortedInsert(toot, allocator);
              var jstr = toot.get("content").?.value.String;
              var html = json_lib.jsonStrDecode(jstr, allocator) catch unreachable;
              var root = html_lib.parse(html, allocator);
              html_lib.search(root);
              cache_update(toot);

              for(images.toSlice()) |image| {
                const imgUrl = image.Object.get("preview_url").?.value.String;
                warn("toot #{} has img {}\n", toot.id(), imgUrl);
                mediaget(toot, imgUrl);
              }
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

fn mediaback(command: *thread.Command) void {
  const reqres = command.verb.http;
  const tootpic = allocator.create(gui.TootPic) catch unreachable;
  tootpic.toot = reqres.toot;
  tootpic.pic = reqres.body;
  warn("mediaback toot #{} {*} \n", tootpic.toot.id(), &tootpic.toot);
  tootpic.toot.addImg(tootpic.pic);
  gui.schedule(gui.toot_media_schedule, @ptrCast(*c_void, tootpic));
}

fn photoback(command: *thread.Command) void {
  const reqres = command.verb.http;
  var account = reqres.toot.get("account").?.value.Object;
  const acct = account.get("acct").?.value.String;
  warn("photoback! acct {} type {} size {}\n", acct, reqres.content_type, reqres.body.len);
  dbfile.write(acct, "photo", reqres.body, allocator) catch unreachable;
  const cAcct = util.sliceToCstr(allocator, acct);
  gui.schedule(gui.update_author_photo_schedule, @ptrCast(*c_void, cAcct));
}

fn profileback(command: *thread.Command) void {
  const reqres = command.verb.http;
  reqres.column.account = command.verb.http.tree.root.Object;
  gui.schedule(gui.update_column_ui_schedule, @ptrCast(*c_void, reqres.column));
}

fn cache_update(toot: *toot_lib.Type) void {
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
    column.inError = false;
    column.refreshing = false;
    column_refresh(column);
  }
  if (command.id == 3) { // add column
    var colInfo = allocator.create(config.ColumnInfo) catch unreachable;
    colInfo.reset();
    colInfo.toots = toot_list.TootList.init();
    colInfo.last_check = 0;
    settings.columns.append(colInfo) catch unreachable;
    var colConfig = allocator.create(config.ColumnConfig) catch unreachable;
    colInfo.config = colConfig;
    colInfo.config.title = ""[0..];
    colInfo.config.filter = "mastodon.example.com"[0..];
    colInfo.filter = filter_lib.parse(allocator, colInfo.config.filter);
    gui.schedule(gui.add_column_schedule, @ptrCast(*c_void, colInfo));
    config.writefile(settings, "config.json");
  }
  if (command.id == 4) { // config changed
    const column = command.verb.column;
    warn("gui col config {}\n", column.config.title);
    column.inError = false;
    column.refreshing = false;
    column_refresh(column);
    config.writefile(settings, "config.json");
  }
  if (command.id == 5) { // column remove
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
  if (command.id == 9) { // imgonly button
    const column = command.verb.column;
    column.config.img_only = !column.config.img_only;
    config.writefile(settings, "config.json");
    gui.schedule(gui.update_column_toots_rebuild_schedule, @ptrCast(*c_void, column));
  }
  if (command.id == 10) { // window size changed
    config.writefile(settings, "config.json");
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
    const since = now - column.last_check;
    if(since > refresh) {
      column_refresh(column);
    } else {
      //warn("col {} is fresh for {} sec\n", column.makeTitle(), refresh-since);
    }
  }
}

fn column_refresh(column: *config.ColumnInfo) void {
  if(column.refreshing) {
    warn("column {} in {} Ignoring request.\n", column.makeTitle(), if (column.inError) "error!" else "progress.");
  } else {
    warn("column http get {}\n", column.makeTitle());
    column.refreshing = true;
    columnget(column);
  }
}
