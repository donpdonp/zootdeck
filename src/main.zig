// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = util.log;
const CAllocator = std.heap.c_allocator;
const stdout = std.io.getStdOut();
var LogAllocator = std.heap.loggingAllocator(CAllocator, stdout.outStream());
var GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = GeneralPurposeAllocator.allocator(); // take the ptr in a separate step

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
const html_lib = @import("./html.zig");
const filter_lib = @import("./filter.zig");

var settings: config.Settings = undefined;

pub fn main() !void {
    try thread.init(alloc);
    hello(); // wait for thread.init so log entry for main thread will have a name
    try initialize(alloc);

    if (config.readfile(config.config_file_path(), "config.json")) |config_data| {
        settings = config_data;
        try gui.init(alloc, &settings);
        const dummy_payload = try alloc.create(thread.CommandVerb);
        _ = try thread.create("gui", gui.go, dummy_payload, guiback);
        _ = try thread.create("heartbeat", heartbeat.go, dummy_payload, heartback);
        while (true) {
            statewalk(alloc);
            util.log("thread.wait()/epoll", .{});
            thread.wait(); // main ipc listener
        }
    } else |err| {
        warn("config error: {!}", .{err});
    }
}

fn initialize(allocator: std.mem.Allocator) !void {
    try config.init(allocator);
    try heartbeat.init(allocator);
    try statemachine.init(allocator);
    try db.init(allocator);
    try dbfile.init(allocator);
}

fn statewalk(allocator: std.mem.Allocator) void {
    if (statemachine.state == statemachine.States.Init) {
        statemachine.setState(statemachine.States.Setup); // transition
        var ram = allocator.alloc(u8, 1) catch unreachable;
        ram[0] = 1;
        gui.schedule(gui.show_main_schedule, @ptrCast(&ram));
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

    if (statemachine.state == statemachine.States.Setup) {
        statemachine.setState(statemachine.States.Running); // transition
        columns_net_freshen(allocator);
    }
}

fn hello() void {
    util.log("zootdeck {s} {s} tid {}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), thread.self() });
}

fn columnget(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    httpInfo.url = util.mastodonExpandUrl(column.filter.host(), column.config.token != null, allocator);
    httpInfo.verb = .get;
    httpInfo.token = null;
    if (column.config.token) |tokenStr| {
        httpInfo.token = tokenStr;
    }
    httpInfo.column = column;
    httpInfo.response_code = 0;
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

fn oauthcolumnget(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    auth.oauthClientRegister(allocator, httpInfo, column.filter.host());
    httpInfo.token = null;
    httpInfo.column = column;
    httpInfo.response_code = 0;
    httpInfo.verb = .post;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    _ = thread.create("net", net.go, verb, oauthback) catch unreachable;
    //  defer thread.destroy(allocator, netthread);
}

fn oauthtokenget(column: *config.ColumnInfo, code: []const u8, allocator: std.mem.Allocator) void {
    var verb = allocator.create(thread.CommandVerb) catch unreachable;
    var httpInfo = allocator.create(config.HttpInfo) catch unreachable;
    auth.oauthTokenUpgrade(allocator, httpInfo, column.filter.host(), code, column.oauthClientId.?, column.oauthClientSecret.?);
    httpInfo.token = null;
    httpInfo.column = column;
    httpInfo.response_code = 0;
    httpInfo.verb = .post;
    verb.http = httpInfo;
    gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(httpInfo)));
    _ = thread.create("net", net.go, verb, oauthtokenback) catch unreachable;
}

fn oauthtokenback(command: *thread.Command) void {
    //warn("*oauthtokenback tid {x} {}\n", .{ thread.self(), command });
    const column = command.verb.http.column;
    const http = command.verb.http;
    if (http.response_code >= 200 and http.response_code < 300) {
        const tree = command.verb.http.tree;
        //const rootJsonType = @TypeOf(tree.root);
        if (true) { // todo: rootJsonType == std.json.ObjectMap) {
            if (tree.object.get("access_token")) |cid| {
                column.config.token = cid.string;
                config.writefile(settings, "config.json");
                column.last_check = 0;
                profileget(column, alloc);
                gui.schedule(gui.update_column_config_oauth_finalize_schedule, @as(*anyopaque, @ptrCast(column)));
            }
        } else {
            warn("*oauthtokenback json err body {}", .{http.body});
        }
    } else {
        //warn("*oauthtokenback net err {}\n", .{http.response_code});
    }
}

fn oauthback(command: *thread.Command) void {
    //warn("*oauthback tid {x} {}\n", .{ thread.self(), command });
    const column = command.verb.http.column;
    const http = command.verb.http;
    if (http.response_code >= 200 and http.response_code < 300) {
        const tree = command.verb.http.tree;
        const rootJsonType = @TypeOf(tree);
        if (true) { //todo: rootJsonType == std.json.Value) {
            if (tree.object.get("client_id")) |cid| {
                column.oauthClientId = cid.string;
            }
            if (tree.object.get("client_secret")) |cid| {
                column.oauthClientSecret = cid.string;
            }
            //warn("*oauthback client id {s} secret {s}\n", .{ column.oauthClientId, column.oauthClientSecret });
            gui.schedule(gui.column_config_oauth_url_schedule, @as(*anyopaque, @ptrCast(column)));
        } else {
            warn("*oauthback json type err {} {s}", .{ rootJsonType, http.body });
        }
    } else {
        //warn("*oauthback net err {}\n", .{http.response_code});
    }
}

fn netback(command: *thread.Command) void {
    warn("*netback {*} {} {*}", .{ command, command.id, command.verb });
    if (command.id == 1) {
        gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(command.verb.http)));
        var column = command.verb.http.column;
        warn("netback adding toots to column {s}", .{util.json(column.config.title)});
        column.refreshing = false;
        column.last_check = config.now();
        if (command.verb.http.response_code >= 200 and command.verb.http.response_code < 300) {
            if (command.verb.http.body.len > 0) {
                const tree = command.verb.http.tree; //.array;
                switch (tree.*) {
                    .array => column_load(column, tree.array),
                    .object => {
                        if (tree.object.get("error")) |err| {
                            warn("netback json err {s}", .{err.string});
                        }
                    },
                    else => warn("!netback json unknown root tagtype {!}", .{tree}),
                }
            } else { // empty body
                column.inError = true;
            }
        } else {
            column.inError = true;
        }
        gui.schedule(gui.update_column_toots_schedule, @ptrCast(column));
    }
}

fn column_load(column: *config.ColumnInfo, tree: std.json.Array) void {
    column.inError = false;
    warn("netback payload is array len {}", .{tree.items.len});
    for (tree.items) |jsonValue| {
        const item = jsonValue.object;
        warn("netback item {*} item.keys has id #{s}", .{ &item, if (item.contains("id")) item.get("id").?.string else "MISSING" });
        var toot = toot_lib.Type.init(&item, alloc);
        warn("netback toot {*} {*} hashmap.keys has id #{s}", .{ toot, toot.hashmap, if (toot.hashmap.contains("id")) toot.hashmap.get("id").?.string else "MISSING" });
        const id = toot.id();
        if (column.toots.contains(toot)) {
            warn("netback dupe toot skipped {*} #{s} already in column", .{ toot, id });
        } else {
            column.toots.sortedInsert(toot, alloc);
            warn("netback inserted toot #{s}", .{id});
            const html = toot.get("content").?.string;
            const root = html_lib.parse(html);
            html_lib.search(root);
            cache_update(toot, alloc);

            const images = toot.get("media_attachments").?.array;
            media_attachments(toot, images);
        }
    }
}

fn media_attachments(toot: *toot_lib.Type, images: std.json.Array) void {
    for (images.items) |image| {
        const img_url_raw = image.object.get("preview_url").?;
        if (img_url_raw == .string) {
            const img_url = img_url_raw.string;
            warn("toot #{s} has img {s}", .{ toot.id(), img_url });
            mediaget(toot, img_url, alloc);
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
    tootpic.pic = reqres.body;
    warn("mediaback toot #{s} tootpic.toot {*} adding 1 img\n", .{ tootpic.toot.id(), tootpic.toot });
    tootpic.toot.addImg(tootpic.pic);
    gui.schedule(gui.toot_media_schedule, @as(*anyopaque, @ptrCast(tootpic)));
}

fn photoback(command: *thread.Command) void {
    thread.destroy(command.actor); // TODO: thread one-shot
    const reqres = command.verb.http;
    var account = reqres.toot.get("account").?.object;
    const acct = account.get("acct").?.string;
    //warn("photoback! acct {s} type {s} size {}\n", .{ acct, reqres.content_type, reqres.body.len });
    dbfile.write(acct, "photo", reqres.body, alloc) catch unreachable;
    const cAcct = util.sliceToCstr(alloc, acct);
    gui.schedule(gui.update_author_photo_schedule, @as(*anyopaque, @ptrCast(cAcct)));
}

fn profileback(command: *thread.Command) void {
    thread.destroy(command.actor); // TODO: thread one-shot
    const reqres = command.verb.http;
    if (reqres.response_code >= 200 and reqres.response_code < 300) {
        reqres.column.account = reqres.tree.object;
        gui.schedule(gui.update_column_ui_schedule, @as(*anyopaque, @ptrCast(reqres.column)));
    } else {
        //warn("profile fail http status {!}\n", .{reqres.response_code});
    }
}

fn cache_update(toot: *toot_lib.Type, allocator: std.mem.Allocator) void {
    var account = toot.get("account").?.object;
    const acct: []const u8 = account.get("acct").?.string;
    const avatar_url: []const u8 = account.get("avatar").?.string;
    db.write(acct, "photo_url", avatar_url, allocator) catch unreachable;
    const name: []const u8 = account.get("display_name").?.string;
    db.write(acct, "name", name, allocator) catch unreachable;
    if (dbfile.has(acct, "photo", allocator)) {} else {
        photoget(toot, avatar_url, allocator);
    }
}

fn guiback(command: *thread.Command) void {
    warn("guiback() tid {} command {} {}", .{ thread.self(), &command, command });
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
        const colConfig = alloc.create(config.ColumnConfig) catch unreachable;
        colInfo.config = colConfig.reset();
        colInfo.filter = filter_lib.parse(alloc, colInfo.config.filter);
        gui.schedule(gui.add_column_schedule, @as(*anyopaque, @ptrCast(colInfo)));
        config.writefile(settings, "config.json");
    }
    if (command.id == 4) { // save config params
        const column = command.verb.column;
        warn("guiback save config column title: ({d}){s}", .{ column.config.title.len, column.config.title });
        column.inError = false;
        column.refreshing = false;
        config.writefile(settings, "config.json");
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
        config.writefile(settings, "config.json");
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
        config.writefile(settings, "config.json");
        gui.schedule(gui.update_column_toots_schedule, @as(*anyopaque, @ptrCast(column)));
    }
    if (command.id == 10) { // window size changed
        config.writefile(settings, "config.json");
    }
    if (command.id == 11) { // Quit
        warn("byebye...", .{});
        std.posix.exit(0);
    }
}

fn heartback(command: *thread.Command) void {
    warn("heartback() on tid {} received {}", .{ thread.self(), command.verb });
    columns_net_freshen(alloc);
}

fn columns_net_freshen(allocator: std.mem.Allocator) void {
    for (settings.columns.items) |column| {
        const now = config.now();
        const refresh = 60;
        const since = now - column.last_check;
        if (since > refresh) {
            column_refresh(column, allocator);
        } else {
            //warn("col {} is fresh for {} sec\n", column.makeTitle(), refresh-since);
        }
    }
}

fn column_refresh(column: *config.ColumnInfo, allocator: std.mem.Allocator) void {
    if (column.refreshing) {
        warn("column {s} in {s} Ignoring request.", .{ column.config.title, if (column.inError) @as([]const u8, "error!") else @as([]const u8, "progress.") });
    } else {
        warn("column_refresh http get for title: {s}", .{util.json(column.config.title)});
        column.refreshing = true;
        columnget(column, allocator);
    }
}
