// config.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const util = @import("./util.zig");
//const SortedList = @import("./sorted_list.zig");
var allocator: *Allocator = undefined;

const c = @cImport({
    @cInclude("time.h");
});

pub const Time = c.time_t;

// contains runtime-only values
pub const Settings = struct {
  win_x: i64,
  win_y: i64,
  columns: std.ArrayList(*ColumnInfo)
};

// on-disk format
pub const ConfigFile = struct {
  win_x: i64,
  win_y: i64,
  columns: std.ArrayList(*ColumnConfig)
};

pub const TootType = std.hash_map.HashMap([]const u8,
                                          std.json.Value,
                                          std.mem.hash_slice_u8,
                                          std.mem.eql_slice_u8);
pub const TootList = std.LinkedList(TootType);

pub const ColumnInfo = struct {
  config: *ColumnConfig,
  toots: TootList,
  refreshing: bool,
  inError: bool,

  pub fn reset(self: ColumnInfo) void {
    var other = self;
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
  token: ?[]const u8,
  body: []const u8,
  response_code: c_long,
  tree: std.json.ValueTree,
  column: *ColumnInfo
};


const ConfigError = error{MissingParams};

pub fn init(alloc: *Allocator) !void {
  allocator = alloc;
  var trickZig = false;
  if (trickZig) { return error.BadValue; }
}

pub fn readfile(filename: []const u8) !Settings {
  if (std.os.File.openWriteNoClobber(filename, std.os.File.default_mode)) |*file| {
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
      colInfo.toots = TootList.init();
      warn("colInfo config create/reste check toots {*}\n", &colInfo.toots);
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
  if (std.os.File.openWrite(filename)) |*file| {
    warn("config.write toJson\n");
    var data = util.toJson(allocator, configFile);
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

