// config.zig
const std = @import("std");
const warn = util.log;
const Allocator = std.mem.Allocator;
const util = @import("./util.zig");
const filter_lib = @import("./filter.zig");
const toot_lib = @import("./toot.zig");
const toot_list = @import("./toot_list.zig");
var allocator: Allocator = undefined;

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

// on-disk config
pub const ConfigFile = struct {
    win_x: i64,
    win_y: i64,
    columns: []*ColumnConfig,
};

pub const ColumnInfo = struct {
    config: *ColumnConfig,
    filter: *filter_lib.ptree,
    toots: toot_list.TootList,
    refreshing: bool,
    last_check: Time,
    inError: bool,
    account: ?std.json.ObjectMap,
    oauthClientId: ?[]const u8,
    oauthClientSecret: ?[]const u8,

    const Self = @This();

    pub fn reset(self: *Self) *Self {
        self.account = null;
        self.oauthClientId = null;
        self.oauthClientSecret = null;
        return self;
    }

    pub fn parseFilter(self: *const Self, filter: []const u8) void {
        self.filter = filter_lib.parse(filter);
    }

    pub fn makeTitle(column: *ColumnInfo) []const u8 {
        var out: []const u8 = column.filter.host();
        if (column.config.token) |_| {
            var addon: []const u8 = undefined;
            if (column.account) |account| {
                addon = account.get("acct").?.string;
            } else {
                addon = "_";
            }
            out = std.fmt.allocPrint(allocator, "{s}@{s}", .{ addon, column.filter.host() }) catch unreachable;
        }
        return out;
    }
};

pub const ColumnConfig = struct {
    title: []const u8,
    filter: []const u8,
    token: ?[]const u8,
    img_only: bool,

    const Self = @This();

    pub fn reset(self: *Self) *Self {
        self.title = "";
        self.filter = "mastodon.example.com";
        self.token = null;
        return self;
    }
};

pub const LoginInfo = struct {
    username: []const u8,
    password: []const u8,
};

pub const HttpInfo = struct {
    url: []const u8,
    verb: enum {
        get,
        post,
    },
    token: ?[]const u8,
    post_body: []const u8,
    body: []const u8,
    content_type: []const u8,
    response_code: c_long,
    tree: std.json.Parsed(std.json.Value),
    column: *ColumnInfo,
    toot: *toot_lib.Type,
};

pub const ColumnAuth = struct {
    code: []const u8,
    column: *ColumnInfo,
};

const ConfigError = error{MissingParams};

pub fn init(alloc: Allocator) !void {
    allocator = alloc;
}

pub fn config_file_path() []const u8 {
    const home_path = std.posix.getenv("HOME").?;
    const home_dir = std.fs.openDirAbsolute(home_path, .{}) catch unreachable;
    const config_dir_path = std.fs.path.join(allocator, &.{ home_path, ".config", "zootdeck" }) catch unreachable;
    home_dir.makePath(config_dir_path) catch unreachable; // try every time
    const config_dir = std.fs.openDirAbsolute(config_dir_path, .{}) catch unreachable;
    const filename = "config.json";
    const config_path = std.fs.path.join(allocator, &.{ config_dir_path, filename }) catch unreachable;
    config_dir.access(filename, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            warn("Warning: creating new {s}", .{config_path});
            config_dir.writeFile(.{ .sub_path = filename, .data = "{}\n" }) catch unreachable;
        },
        else => {
            warn("readfile err {any}", .{err});
            unreachable;
        },
    };
    return config_path;
}

pub fn readfile(filename: []const u8) !Settings {
    util.log("config file {s}", .{filename});
    const json = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
    var settings = try read(json);
    settings.config_path = filename;
    return settings;
}

pub fn read(json: []const u8) !Settings {
    const value_tree = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    var root = value_tree.value.object;
    var settings = allocator.create(Settings) catch unreachable;
    settings.columns = std.ArrayList(*ColumnInfo).init(allocator);

    if (root.get("win_x")) |w| {
        warn("config: win_x", .{});
        settings.win_x = w.integer;
    } else {
        settings.win_x = 800;
    }
    if (root.get("win_y")) |h| {
        warn("config: win_y", .{});
        settings.win_y = h.integer;
    } else {
        settings.win_y = 600;
    }
    if (root.get("columns")) |columns| {
        warn("config: columns {}", .{columns.array.items.len});
        for (columns.array.items) |value| {
            var colInfo = allocator.create(ColumnInfo) catch unreachable;
            _ = colInfo.reset();
            colInfo.toots = toot_list.TootList.init();
            const colconfig = allocator.create(ColumnConfig) catch unreachable;
            colInfo.config = colconfig;
            const title = value.object.get("title").?.string;
            colInfo.config.title = title;
            const filter = value.object.get("filter").?.string;
            colInfo.config.filter = filter;
            colInfo.filter = filter_lib.parse(allocator, filter);
            const tokenTag = value.object.get("token");
            if (tokenTag) |tokenKV| {
                if (@TypeOf(tokenKV) == []const u8) {
                    colInfo.config.token = tokenKV.value.string;
                } else {
                    colInfo.config.token = null;
                }
            } else {
                colInfo.config.token = null;
            }
            const img_only = value.object.get("img_only").?.bool;
            colInfo.config.img_only = img_only;
            settings.columns.append(colInfo) catch unreachable;
            warn("config read colinfo {*}", .{colInfo});
        }
    }
    return settings.*;
}

pub fn writefile(settings: Settings, filename: []const u8) void {
    var configFile = allocator.create(ConfigFile) catch unreachable;
    configFile.win_x = settings.win_x;
    configFile.win_y = settings.win_y;
    var column_infos = std.ArrayList(*ColumnConfig).init(allocator);
    for (settings.columns.items) |column| {
        warn("config.writefile writing column {s}", .{column.config.title});
        column_infos.append(column.config) catch unreachable;
    }
    configFile.columns = column_infos.items;

    if (std.fs.cwd().createFile(filename, .{ .truncate = true })) |*file| {
        std.json.stringify(configFile, std.json.StringifyOptions{}, file.writer()) catch unreachable;
        warn("config saved. {s} {} bytes", .{ filename, file.getPos() catch unreachable });
        file.close();
    } else |err| {
        warn("config save fail. {!}", .{err});
    } // existing file is OK
}

pub fn now() Time {
    var t: Time = undefined;
    _ = c.time(&t);
    return t;
}

const assert = @import("std").debug.assert;
test "read" {
    const ret = read("{\"url\":\"abc\"}");
    if (ret) {
        assert(true);
    } else |err| {
        warn("warn: {!}", .{err});
        assert(false);
    }
}
