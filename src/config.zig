// config.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const util = @import("./util.zig");
const Json = @import("./json.zig");
const toot_lib = @import("./toot.zig");
const toot_list = @import("./toot_list.zig");
var allocator: *Allocator = undefined;

const c = @cImport({
  @cInclude("time.h");
});

pub const Time = c.time_t;

// contains runtime-only values
pub const Settings = struct {
  win_x: i64,
  win_y: i64,
  columns: std.ArrayList(*ColumnInfo),
  config_path: []const u8,
};

// on-disk format
pub const ConfigFile = struct {
  win_x: i64,
  win_y: i64,
  columns: std.ArrayList(*ColumnConfig)
};

pub const ColumnInfo = struct {
  config: *ColumnConfig,
  toots: toot_list.TootList,
  refreshing: bool,
  inError: bool,
  account: ?std.hash_map.HashMap([]const u8,std.json.Value,std.mem.hash_slice_u8,std.mem.eql_slice_u8),
  oauthClientId: ?[]const u8,
  oauthClientSecret: ?[]const u8,

  pub fn reset(self: ColumnInfo) void {
    var other = self;
  }

  pub fn makeTitle(column: *ColumnInfo) []const u8 {
    var out: []const u8 = column.config.url;
    if(column.config.token) |tkn| {
      var addon: []const u8 = undefined;
      if(column.account) |account| {
        addon = account.get("acct").?.value.String;
      } else {
        addon = "_";
      }
      out = std.fmt.allocPrint(allocator, "{}@{}", addon, column.config.url) catch unreachable;
    }
    return out;
  }
};

pub const ColumnConfig = struct {
  title: []const u8,
  url: []const u8,
  token: ?[]const u8,
  last_check: Time,
};

pub const LoginInfo = struct {
  username: []const u8,
  password: []const u8
};

pub const HttpInfo = struct {
  url: []const u8,
  verb: enum { get, post},
  token: ?[]const u8,
  post_body: []const u8,
  body: []const u8,
  content_type: []const u8,
  response_code: c_long,
  tree: std.json.ValueTree,
  column: *ColumnInfo,
  toot: toot_lib.Toot()
};

pub const ColumnAuth = struct {
  code: []const u8,
  column: *ColumnInfo
};

const ConfigError = error{MissingParams};

pub fn init(alloc: *Allocator) !void {
  allocator = alloc;
  var trickZig = false;
  if (trickZig) { return error.BadValue; }
}

pub fn readfile(filename: []const u8) !Settings {
  if (std.fs.File.openWriteNoClobber(filename, std.fs.File.default_mode)) |*file| {
    try file.write("{}\n");
    warn("Warning: creating new {}\n", filename);
    file.close();
  } else |err| {} // existing file is OK

  var json = try std.io.readFileAlloc(allocator, filename);
  return read(json);
}

pub fn read(json: []const u8) !Settings {
  var json_parser = std.json.Parser.init(allocator, false);
  var value_tree = try json_parser.parse(json);
  var settings = allocator.create(Settings) catch unreachable;
  var root = value_tree.root.Object;
  settings.columns = std.ArrayList(*ColumnInfo).init(allocator);

  if (root.get("win_x")) |w| {
    settings.win_x = w.value.Integer;
  } else {
    settings.win_x = 800;
  }
  if (root.get("win_y")) |h| {
    settings.win_y = h.value.Integer;
  } else {
    settings.win_y = 600;
  }
  if (root.get("columns")) |columns| {
    for(columns.value.Array.toSlice()) |value| {
      var colInfo = allocator.create(ColumnInfo) catch unreachable;
      colInfo.reset();
      colInfo.toots = toot_list.TootList.init();
      var colconfig = allocator.create(ColumnConfig) catch unreachable;
      colInfo.config = colconfig;
      var title = value.Object.get("title").?.value.String;
      colInfo.config.title = title;
      var url = value.Object.get("url").?.value.String;
      colInfo.config.url = url;
      var tokenTag = value.Object.get("token");
      if(tokenTag) |tokenKV| {
        if(@TagType(std.json.Value)(tokenKV.value) == .String) {
          colInfo.config.token = tokenKV.value.String;
        } else {
          colInfo.config.token = null;
        }
      } else {
        colInfo.config.token = null;
      }
      var last_check = value.Object.get("last_check").?.value.Integer;
      colInfo.config.last_check = last_check;
      settings.columns.append(colInfo) catch unreachable;
    }
  } else {
    warn("missing columns\n");
  }
  return settings.*;
}

pub fn writefile(settings: Settings, filename: []const u8) void {
  var configFile = allocator.create(ConfigFile) catch unreachable;
  configFile.win_x = @intCast(c_int, settings.win_x);
  configFile.win_y = @intCast(c_int, settings.win_y);
  configFile.columns = std.ArrayList(*ColumnConfig).init(allocator);
  for(settings.columns.toSlice()) |column, idx| {
    configFile.columns.append(column.config) catch unreachable;
  }
  if (std.fs.File.openWrite(filename)) |*file| {
    warn("config.write toJson\n");
    var data = Json.toJson(allocator, configFile);
    file.write(data) catch unreachable;
    warn("config saved. {} {} bytes\n", filename, data.len);
    file.close();
  } else |err| {
    warn("config save fail. {}\n", err);
  } // existing file is OK
}

pub fn now() Time {
  var t: Time = undefined;
  _ = c.time(&t);
  return t;
}

const assert = @import("std").debug.assert;
test "read" {
  var ret = read("{\"url\":\"abc\"}");
  if (ret) |value| {
    assert(true);
  } else |err| {
    warn("warn: {}\n", err);
    assert(false);
  }
}

