// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = util.log;
var GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = GeneralPurposeAllocator.allocator(); // take the ptr in a separate step

const oauth = @import("./oauth.zig");
const gui = @import("./gui.zig");
const net = @import("./net.zig");
const heartbeat = @import("./heartbeat.zig");
const config = @import("./config.zig");
const thread = @import("./thread.zig");
const db_kv = @import("./db/lmdb.zig");
const db_file = @import("./db/file.zig");
const statemachine = @import("./statemachine.zig");
const util = @import("./util.zig");
const toot_list = @import("./toot_list.zig");
const toot_lib = @import("./toot.zig");
const html_lib = @import("./html.zig");
const filter_lib = @import("./filter.zig");

var settings: config.Settings = undefined;

pub fn main() !void {
    try thread.init(alloc);
    hello(); // wait for thread.init so log entry for main thread will have a name
    try initialize(alloc);

    if (config.readfile(config.config_file_path())) |config_data| {
        settings = config_data;
        try gui.init(alloc, &settings);
        const dummy_payload = try alloc.create(thread.CommandVerb);
        _ = try thread.create("gui", gui.go, dummy_payload, guiback);
        _ = try thread.create("heartbeat", heartbeat.go, dummy_payload, heartback);
        while (true) {
            stateNext(alloc);
            util.log("thread.wait()/epoll", .{});
            thread.wait(); // main ipc listener
        }
    } else |err| {
        warn("config error: {!}", .{err});
    }
}

fn hello() void {
    util.log("zootdeck {s} {s} zig {s}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), builtin.zig_version_string });
}

fn initialize(allocator: std.mem.Allocator) !void {
    try config.init(allocator);
    try heartbeat.init(allocator);
    try db_kv.init(allocator);
    try db_file.init(allocator);
    try statemachine.init();
}

fn stateNext(allocator: std.mem.Allocator) void {
    if (statemachine.state == .Init) {
        statemachine.setState(.Setup); // transition
        gui.schedule(gui.show_main_schedule, null);
        for (settings.columns.items) |column| {
            if (column.config.token) |token| {
                _ = token;
                profileget(column, allocator);
            }
        }
        for (settings.columns.items) |column| {
            gui.schedule(gui.add_column_schedule, column);
        }
    }

    if (statemachine.state == .Setup) {
        statemachine.setState(.Running); // transition
        columns_net_freshen(allocator);
        for (settings.columns.items) |column| {
            column_db_sync(column, allocator);
        }
    }
}

fn columnget(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    httpInfo.url = util.mastodonExpandUrl(column.filter.host(), column.config.token != null, allocator);
    httpInfo.verb = .get;
    httpInfo.token = null;
    if (column.config.token) |tokenStr| {
        httpInfo.token = tokenStr;
    }
    httpInfo.column = column;
    httpInfo.response_code = 0;
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    if (thread.create("net", net.go, verb, netback)) |_| {} else |_| {
        //warn("columnget {!}", .{err});
    }
}

fn profileget(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    httpInfo.url = std.fmt.allocPrint(allocator, "https://{s}/api/v1/accounts/verify_credentials", .{column.filter.host()}) catch unreachable;
    httpInfo.verb = .get;
    httpInfo.token = null;
    if (column.config.token) |tokenStr| {
        httpInfo.token = tokenStr;
    }
    httpInfo.column = column;
    httpInfo.response_code = 0;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    _ = thread.create("net", net.go, verb, profileback) catch unreachable;
}

fn photoget(toot: *toot_lib.Type, url: []const u8, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    httpInfo.url = url;
    httpInfo.verb = .get;
    httpInfo.token = null;
    httpInfo.response_code = 0;
    httpInfo.toot = toot;
    verb.http = httpInfo;
    _ = thread.create("net", net.go, verb, photoback) catch unreachable;
}

fn mediaget(toot: *toot_lib.Type, url: []const u8, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    verb.http = allocator.create(config.HttpInfo) catch unreachable;
    verb.http.url = url;
    verb.http.verb = .get;
    verb.http.token = null;
    verb.http.response_code = 0;
    verb.http.toot = toot;
    warn("mediaget toot #{s} toot {*} verb.http.toot {*}", .{ toot.id(), toot, verb.http.toot });
    _ = thread.create("net", net.go, verb, mediaback) catch unreachable;
}

fn netback(command: *thread.Command) void {
    warn("*netback cmd#{}", .{command.id});
    if (command.id == 1) {
        gui.schedule(gui.update_column_netstatus_schedule, @ptrCast(command.verb.http));
        var column = command.verb.http.column;
        column.refreshing = false;
        column.last_check = config.now();
        if (http_json_parse(command.verb.http)) |json_response_object| {
            const items = json_response_object.value.array.items[0..1];
            warn("netback adding {} toots to column {s}", .{ items.len, util.json_stringify(column.makeTitle()) });
            cache_save(column, items);
            column_db_sync(column, alloc);
        } else |_| {
            column.inError = true;
        }

        gui.schedule(gui.update_column_toots_schedule, @ptrCast(column));
    }
}

fn http_json_parse(http: *config.HttpInfo) !std.json.Parsed(std.json.Value) {
    if (http.response_ok()) {
        if (http.body.len > 0) {
            if (http.content_type.len == 0 or http.content_type_json()) {
                if (std.json.parseFromSlice(std.json.Value, alloc, http.body, .{ .allocate = .alloc_always })) |json_parsed| {
                    switch (json_parsed.value) {
                        .array => return json_parsed,
                        .object => {
                            if (json_parsed.value.object.get("error")) |err| {
                                warn("netback mastodon err {s}", .{err.string});
                                return error.MastodonReponseErr;
                            } else {
                                warn("netback mastodon unknown response {}", .{json_parsed.value.object});
                                return error.MastodonReponseErr;
                            }
                        },
                        else => {
                            warn("!netback json unknown root tagtype {!}", .{json_parsed.value});
                            return error.JSONparse;
                        },
                    }
                } else |err| {
                    warn("net json parse err {!}", .{err});
                    http.response_code = 1000;
                    return error.JSONparse;
                }
            } else {
                return error.HTTPContentNotJson;
            }
        } else { // empty body
            return error.JSONparse;
        }
    } else {
        return error.HTTPResponseNot2xx;
    }
}

fn column_db_sync(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    const post_ids = db_kv.scan(&.{ "posts", column.filter.hostname }, allocator) catch unreachable;
    warn("column_db_sync {s} scan found {} items", .{ column.makeTitle(), post_ids.len });
    for (post_ids) |id| {
        const post_json = db_file.read(&.{ "posts", column.filter.hostname, id }, allocator);
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, post_json, .{}) catch unreachable;
        const toot: *toot_lib.Type = toot_lib.Type.init(parsed.value, allocator);
        if (!column.toots.contains(toot)) {
            column.toots.sortedInsert(toot, alloc);
            if (toot.get("media_attachments")) |images| { // media is not cached (yet), fetch now
                media_attachments(toot, images.array);
            }
            warn("column_db_sync inserted {*} #{s} count {}", .{ toot, toot.id(), column.toots.count() });
            const acct = toot.acct() catch unreachable;
            if (db_file.has(&.{ "accounts", acct }, "photo", allocator)) {
                const cAcct = util.sliceToCstr(alloc, acct);
                gui.schedule(gui.update_author_photo_schedule, @ptrCast(cAcct));
            }
        } else {
            warn("column_db_sync ignored dupe #{s}", .{toot.id()});
        }
    }
    gui.schedule(gui.update_column_toots_schedule, @ptrCast(column));
}

fn cache_save(column: *config.ColumnInfo, items: []std.json.Value) void {
    column.inError = false;
    warn("cache_load parsed count {} adding to {s}", .{ items.len, column.makeTitle() });
    for (items) |json_value| {
        const toot = toot_lib.Type.init(json_value, alloc);
        cache_write_post(column.filter.hostname, toot, alloc);
    }
}

fn media_attachments(toot: *toot_lib.Type, images: std.json.Array) void {
    for (images.items) |image| {
        const img_url_raw = image.object.get("preview_url").?;
        if (img_url_raw == .string) {
            const img_url = img_url_raw.string;
            warn("toot #{s} has media {s}", .{ toot.id(), img_url });
            if (!toot.containsImgUrl(img_url)) {
                // mediaget(toot, img_url, alloc);
            }
        } else {
            warn("WARNING: image json 'preview_url' is not String: {}", .{img_url_raw});
        }
    }
}

fn mediaback(command: *thread.Command) void {
    thread.destroy(command.actor); // TODO: thread one-shot
    const reqres = command.verb.http;
    const tootpic = alloc.create(gui.TootPic) catch unreachable;
    tootpic.toot = reqres.toot;
    const url_ram = alloc.dupe(u8, reqres.url) catch unreachable;
    const body_ram = alloc.dupe(u8, reqres.body) catch unreachable;
    const img = toot_lib.Img{ .url = url_ram, .bytes = body_ram };
    tootpic.img = img;
    warn("mediaback toot #{s} tootpic.toot {*} adding 1 img", .{ tootpic.toot.id(), tootpic.toot });
    tootpic.toot.addImg(img);
    gui.schedule(gui.toot_media_schedule, @as(*anyopaque, @ptrCast(tootpic)));
}

fn photoback(command: *thread.Command) void {
    thread.destroy(command.actor); // TODO: thread one-shot
    const reqres = command.verb.http;
    var account = reqres.toot.get("account").?.object;
    const acct = account.get("acct").?.string;
    warn("photoback! acct {s} type {s} size {}", .{ acct, reqres.content_type, reqres.body.len });
    db_file.write(&.{ "accounts", acct }, "photo", reqres.body, alloc) catch unreachable;
    const cAcct = util.sliceToCstr(alloc, acct);
    gui.schedule(gui.update_author_photo_schedule, @as(*anyopaque, @ptrCast(cAcct)));
}

fn profileback(command: *thread.Command) void {
    thread.destroy(command.actor); // TODO: thread one-shot
    const reqres = command.verb.http;
    if (reqres.response_code >= 200 and reqres.response_code < 300) {
        reqres.column.account = reqres.tree.value.object;
        gui.schedule(gui.update_column_ui_schedule, @as(*anyopaque, @ptrCast(reqres.column)));
    } else {
        //warn("profile fail http status {!}", .{reqres.response_code});
    }
}

fn cache_write_post(host: []const u8, toot: *toot_lib.Type, allocator: std.mem.Allocator) void {
    var account = toot.get("account").?.object;

    // index post by host and date
    const toot_created_at = toot.get("created_at").?.string;
    const posts_host_date = util.strings_join_separator(&.{ "posts", host }, ':', allocator); // todo
    db_kv.write(posts_host_date, toot_created_at, toot.id(), allocator) catch unreachable;
    // save post json
    const json = util.json_stringify(toot.hashmap);
    if (db_file.write(&.{ "posts", host }, toot.id(), json, alloc)) |_| {} else |_| {}

    // index avatar url
    const avatar_url: []const u8 = account.get("avatar").?.string;
    const toot_acct = toot.acct() catch unreachable;
    const photos_acct = std.fmt.allocPrint(allocator, "photos:{s}", .{toot_acct}) catch unreachable;
    db_kv.write(photos_acct, "url", avatar_url, allocator) catch unreachable;

    // index display name
    const name: []const u8 = account.get("display_name").?.string;
    db_kv.write(photos_acct, "name", name, allocator) catch unreachable;

    if (!db_file.has(&.{ "accounts", toot_acct }, "photo", allocator)) {
        photoget(toot, avatar_url, allocator);
    }
}

fn guiback(command: *thread.Command) void {
    warn("guiback cmd#{}", .{command.id});
    if (command.id == 1) {
        var ram = alloc.alloc(u8, 1) catch unreachable;
        ram[0] = 1;
        gui.schedule(gui.show_main_schedule, @ptrCast(&ram));
    }
    if (command.id == 2) { // refresh button
        const column = command.verb.column;
        column.inError = false;
        column.refreshing = false;
        column_refresh(column, alloc);
    }
    if (command.id == 3) { // add column
        var colInfo = alloc.create(config.ColumnInfo) catch unreachable;
        _ = colInfo.reset();
        colInfo.toots = toot_list.TootList.init();
        colInfo.last_check = 0;
        settings.columns.append(colInfo) catch unreachable;
        warn("add column: settings.columns.len {}", .{settings.columns.items.len});
        const colConfig = alloc.create(config.ColumnConfig) catch unreachable;
        colInfo.config = colConfig.reset();
        colInfo.filter = filter_lib.parse(alloc, colInfo.config.filter);
        gui.schedule(gui.add_column_schedule, @as(*anyopaque, @ptrCast(colInfo)));
        config.writefile(settings, config.config_file_path());
    }
    if (command.id == 4) { // save config params
        const column = command.verb.column;
        warn("guiback save config column title: ({d}){s}", .{ column.config.title.len, column.config.title });
        column.inError = false;
        column.refreshing = false;
        config.writefile(settings, config.config_file_path());
    }
    if (command.id == 5) { // column remove
        const column = command.verb.column;
        warn("gui col remove {s}", .{column.config.title});
        //var colpos: usize = undefined;
        for (settings.columns.items, 0..) |col, idx| {
            if (col == column) {
                _ = settings.columns.orderedRemove(idx);
                break;
            }
        }
        config.writefile(settings, config.config_file_path());
        gui.schedule(gui.column_remove_schedule, @as(*anyopaque, @ptrCast(column)));
    }
    if (command.id == 6) { //oauth
        const column = command.verb.column;
        if (column.oauthClientId) |id| {
            _ = id;
            gui.schedule(gui.column_config_oauth_url_schedule, @as(*anyopaque, @ptrCast(column)));
        } else {
            oauthcolumnget(column, alloc);
        }
    }
    if (command.id == 7) { //oauth activate
        const myAuth = command.verb.auth.*;
        warn("oauth authorization {s}", .{myAuth.code});
        oauthtokenget(myAuth.column, myAuth.code, alloc);
    }
    if (command.id == 8) { //column config changed
        const column = command.verb.column;
        warn("guiback: column config changed for column title ({d}){s}", .{ column.config.title.len, column.config.title });
        // partial reset
        column.oauthClientId = null;
        column.oauthClientSecret = null;
        gui.schedule(gui.update_column_ui_schedule, @as(*anyopaque, @ptrCast(column)));
        gui.schedule(gui.update_column_toots_schedule, @as(*anyopaque, @ptrCast(column)));
        // throw out toots in the toot list not from the new host
        column_refresh(column, alloc);
    }
    if (command.id == 9) { // image-only button
        const column = command.verb.column;
        column.config.img_only = !column.config.img_only;
        config.writefile(settings, config.config_file_path());
        gui.schedule(gui.update_column_toots_schedule, @as(*anyopaque, @ptrCast(column)));
    }
    if (command.id == 10) { // window size changed
        config.writefile(settings, config.config_file_path());
    }
    if (command.id == 11) { // Quit
        warn("byebye...", .{});
        std.posix.exit(0);
    }
}

fn heartback(command: *thread.Command) void {
    warn("heartback() on tid {} received {}", .{ thread.self(), command.verb });
    //columns_net_freshen(alloc);
}

fn columns_net_freshen(allocator: std.mem.Allocator) void {
    warn("columns_net_freshen", .{});
    for (settings.columns.items) |column| {
        const now = config.now();
        const refresh = 60;
        const since = now - column.last_check;
        if (since > refresh) {
            column_refresh(column, allocator);
        } else {
            //warn("col {} is fresh for {} sec", column.makeTitle(), refresh-since);
        }
    }
}

fn column_refresh(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    if (column.refreshing) {
        warn("column {s} in {s} Ignoring request.", .{ column.config.title, if (column.inError) @as([]const u8, "error!") else @as([]const u8, "progress.") });
    } else {
        warn("column_refresh http get for title: {s}", .{util.json_stringify(column.makeTitle())});
        column.refreshing = true;
        columnget(column, allocator);
    }
}

fn oauthcolumnget(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    oauth.clientRegisterUrl(allocator, httpInfo, column.filter.host());
    httpInfo.token = null;
    httpInfo.column = column;
    httpInfo.response_code = 0;
    httpInfo.verb = .post;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    _ = thread.create("net", net.go, verb, oauthback) catch unreachable;
}

fn oauthtokenget(column: *config.ColumnInfo, code: []const u8, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    oauth.tokenUpgradeUrl(allocator, httpInfo, column.filter.host(), code, column.oauthClientId.?, column.oauthClientSecret.?);
    httpInfo.token = null;
    httpInfo.column = column;
    httpInfo.response_code = 0;
    httpInfo.verb = .post;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    _ = thread.create("net", net.go, verb, oauthtokenback) catch unreachable;
}

fn oauthtokenback(command: *thread.Command) void {
    //warn("*oauthtokenback tid {x} {}", .{ thread.self(), command });
    const column = command.verb.http.column;
    const http = command.verb.http;
    if (http.response_code >= 200 and http.response_code < 300) {
        if (std.json.parseFromSlice(std.json.Value, command.actor.allocator, http.body, .{ .allocate = .alloc_always })) |json_parsed| {
            if (json_parsed.value == .object) {
                if (json_parsed.value.object.get("access_token")) |cid| {
                    column.config.token = cid.string;
                    config.writefile(settings, config.config_file_path());
                    column.last_check = 0;
                    profileget(column, alloc);
                    gui.schedule(gui.update_column_config_oauth_finalize_schedule, @as(*anyopaque, @ptrCast(column)));
                }
            } else {
                warn("*oauthtokenback json err body {s}", .{http.body});
            }
        } else |err| {
            warn("oauthtokenback json parse err {}", .{err});
        }
    } else {
        warn("oauthtokenback net err {d}", .{http.response_code});
    }
}

fn oauthback(command: *thread.Command) void {
    //warn("*oauthback tid {x} {}", .{ thread.self(), command });
    const column = command.verb.http.column;
    const http = command.verb.http;
    if (http.response_code >= 200 and http.response_code < 300) {
        if (std.json.parseFromSlice(std.json.Value, command.actor.allocator, http.body, .{ .allocate = .alloc_always })) |json_parsed| {
            if (json_parsed.value == .object) {
                if (json_parsed.value.object.get("client_id")) |cid| {
                    column.oauthClientId = cid.string;
                }
                if (json_parsed.value.object.get("client_secret")) |cid| {
                    column.oauthClientSecret = cid.string;
                }
                //warn("*oauthback client id {s} secret {s}", .{ column.oauthClientId, column.oauthClientSecret });
                gui.schedule(gui.column_config_oauth_url_schedule, @as(*anyopaque, @ptrCast(column)));
            } else {
                warn("*oauthback json type err {} {s}", .{ json_parsed.value, http.body });
            }
        } else |err| {
            warn("oauthback json parse err {}", .{err});
        }
    } else {
        warn("*oauthback net err {}", .{http.response_code});
    }
}
