// config.zig
const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
const util = @import("./util.zig");
const filter_lib = @import("./filter.zig");
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
    account: ?std.StringHashMap(std.json.Value),
    oauthClientId: ?[]const u8,
    oauthClientSecret: ?[]const u8,

    const Self = @This();

    pub fn reset(self: *const Self) void { _ = self; }

    pub fn parseFilter(self: *const Self, filter: []const u8) void {
        self.filter = filter_lib.parse(filter);
    }

    pub fn makeTitle(column: *ColumnInfo) []const u8 {
        var out: []const u8 = column.filter.host();
        if (column.config.token) |tkn| {
            _ = tkn ;
            var addon: []const u8 = undefined;
            if (column.account) |account| {
                addon = account.get("acct").?.String;
            } else {
                addon = "_";
            }
            out = std.fmt.allocPrint(allocator, "{}@{}", .{ addon, column.filter.host() }) catch unreachable;
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
    tree: std.json.ValueTree,
    column: *ColumnInfo,
    toot: *toot_lib.Type,
};

pub const ColumnAuth = struct {
    code: []const u8,
    column: *ColumnInfo,
};

const ConfigError = error{MissingParams};

pub fn init(alloc: *Allocator) !void {
    allocator = alloc;
}

pub fn readfile(filename: []const u8) !Settings {
    if (std.fs.cwd().createFile(filename, .{ .exclusive = true })) |*file| {
        try file.writeAll("{}\n");
        warn("Warning: creating new {}\n", .{filename});
        file.close();
    } else {} // existing file is OK
    var json = try std.fs.cwd().readFileAlloc(allocator, filename, 65535); //max_size?
    return read(json);
}

pub fn read(json: []const u8) !Settings {
    var json_parser = std.json.Parser.init(allocator, false);
    var value_tree = try json_parser.parse(json);
    var settings = allocator.create(Settings) catch unreachable;
    var root = value_tree.root.Object;
    settings.columns = std.ArrayList(*ColumnInfo).init(allocator);

    if (root.get("win_x")) |w| {
        warn("config: win_x\n", .{});
        settings.win_x = w.Integer;
    } else {
        settings.win_x = 800;
    }
    if (root.get("win_y")) |h| {
        warn("config: win_y\n", .{});
        settings.win_y = h.Integer;
    } else {
        settings.win_y = 600;
    }
    if (root.get("columns")) |columns| {
        warn("config: columns {}\n", .{columns.Array.items.len});
        for (columns.Array.items) |value| {
            var colInfo = allocator.create(ColumnInfo) catch unreachable;
            colInfo.reset();
            colInfo.toots = toot_list.TootList.init();
            var colconfig = allocator.create(ColumnConfig) catch unreachable;
            colInfo.config = colconfig;
            var title = value.Object.get("title").?.String;
            colInfo.config.title = title;
            var filter = value.Object.get("filter").?.String;
            colInfo.config.filter = filter;
            colInfo.filter = filter_lib.parse(allocator, filter);
            var tokenTag = value.Object.get("token");
            if (tokenTag) |tokenKV| {
                if (@TypeOf(tokenKV) == []const u8) {
                    colInfo.config.token = tokenKV.value.String;
                } else {
                    colInfo.config.token = null;
                }
            } else {
                colInfo.config.token = null;
            }
            var img_only = value.Object.get("img_only").?.Bool;
            colInfo.config.img_only = img_only;
            settings.columns.append(colInfo) catch unreachable;
        }
    } else {
        warn("missing columns\n", .{});
    }
    return settings.*;
}

pub fn writefile(settings: Settings, filename: []const u8) void {
    var configFile = allocator.create(ConfigFile) catch unreachable;
    configFile.win_x = settings.win_x;
    configFile.win_y = settings.win_y;
    var column_infos = std.ArrayList(*ColumnConfig).init(allocator);
    for (settings.columns.items) |column| {
        column_infos.append(column.config) catch unreachable;
    }
    configFile.columns = column_infos.items;
    if (std.fs.cwd().createFile(filename, .{ .truncate = true })) |*file| {
        warn("config.write toJson\n", .{});
        std.json.stringify(configFile, std.json.StringifyOptions{}, file.writer()) catch unreachable;
        warn("config saved. {} {} bytes\n", .{ filename, file.getPos() });
        file.close();
    } else |err| {
        warn("config save fail. {}\n", .{err});
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
    if (ret) {
        assert(true);
    } else |err| {
        warn("warn: {}\n", .{err});
        assert(false);
    }
}
