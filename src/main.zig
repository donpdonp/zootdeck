// main.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = util.log;
const CAllocator = std.heap.c_allocator;
const stdout = std.io.getStdOut();
var LogAllocator = std.heap.loggingAllocator(CAllocator, stdout.outStream());
var GPAllocator = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = GPAllocator.allocator(); // take the ptr in a separate step

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
    hello();
    initialize(alloc) catch unreachable;

    if (config.readfile(config.config_file_path())) |config_data| {
        settings = config_data;
        try gui.init(alloc, &settings);
        const dummy_payload = alloc.create(thread.CommandVerb) catch unreachable;
        _ = thread.create("gui", gui.go, dummy_payload, guiback) catch unreachable;
        _ = thread.create("heartbeat", heartbeat.go, dummy_payload, heartback) catch unreachable;
        while (true) {
            statewalk(alloc);
            util.log("thread.wait()/epoll", .{});
            thread.wait(); // main ipc listener
        }
    } else |err| {
        warn("config error: {!}\n", .{err});
    }
}

fn initialize(allocator: std.mem.Allocator) !void {
    try config.init(allocator);
    try heartbeat.init(allocator);
    try statemachine.init(allocator);
    try db.init(allocator);
    try dbfile.init();
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
    util.log("zootdeck {s} {s} tid {}\n", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), thread.self() });
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
    warn("mediaget toot #{s} toot {*} verb.http.toot {*}\n", .{ toot.id(), toot, verb.http.toot });
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
            warn("*oauthtokenback json err body {}\n", .{http.body});
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
            warn("*oauthback json type err {}\n{s}\n", .{ rootJsonType, http.body });
        }
    } else {
        //warn("*oauthback net err {}\n", .{http.response_code});
    }
}

fn netback(command: *thread.Command) void {
    warn("*netback tid {x} {}\n", .{ thread.self(), command });
    if (command.id == 1) {
        gui.schedule(gui.update_column_netstatus_schedule, @as(*anyopaque, @ptrCast(command.verb.http)));
        var column = command.verb.http.column;
        column.refreshing = false;
        column.last_check = config.now();
        if (command.verb.http.response_code >= 200 and command.verb.http.response_code < 300) {
            if (command.verb.http.body.len > 0) {
                const tree = command.verb.http.tree.array;
                warn("netback tree is {!}", .{tree});
                if (@TypeOf(tree) == std.json.Array) {
                    column.inError = false;
                    warn("netback payload is array len {}\n", .{tree.items.len});
                    for (tree.items) |jsonValue| {
                        const item = jsonValue.object;
                        const toot = alloc.create(toot_lib.Type) catch unreachable;
                        toot.* = toot_lib.Type.init(item, alloc);
                        const id = toot.id();
                        warn("netback json create toot #{s} {*}\n", .{ id, toot });
                        if (column.toots.contains(toot)) {
                            // dupe
                        } else {
                            const images = toot.get("media_attachments").?.array;
                            column.toots.sortedInsert(toot, alloc);
                            const html = toot.get("content").?.string;
                            //var html = json_lib.jsonStrDecode(jstr, allocator) catch unreachable;
                            const root = html_lib.parse(html);
                            html_lib.search(root);
                            cache_update(toot, alloc);

                            for (images.items) |image| {
                                const img_url_raw = image.object.get("preview_url").?;
                                if (img_url_raw == .string) {
                                    const img_url = img_url_raw.string;
                                    warn("toot #{s} has img {s}\n", .{ toot.id(), img_url });
                                    mediaget(toot, img_url, alloc);
                                } else {
                                    warn("WARNING: image json 'preview_url' is not String: {}", .{img_url_raw});
                                }
                            }
                        }
                    }
                } else if (@TypeOf(tree) == std.json.ObjectMap) {
                    warn("netback json is object");
                    if (tree.object.get("error")) |err| {
                        warn("netback json err {s} \n", .{err.String});
                    }
                } else {
                    //warn("!netback json unknown root tagtype {!}\n", .{tree});
                }
            } else { // empty body
                column.inError = true;
            }
        } else {
            column.inError = true;
        }
        gui.schedule(gui.update_column_toots_schedule, @as(*anyopaque, @ptrCast(column)));
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
    warn("photoback! acct {s} type {s} size {}\n", .{ acct, reqres.content_type, reqres.body.len });
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
    warn("guiback() tid {} command {} {} \n", .{ thread.self(), &command, command });
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
        warn("gui col config {s}\n", .{column.config.title});
        column.inError = false;
        column.refreshing = false;
        config.writefile(settings, "config.json");
    }
    if (command.id == 5) { // column remove
        const column = command.verb.column;
        warn("gui col remove {s}\n", .{column.config.title});
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
        warn("oauth authorization {s}\n", .{myAuth.code});
        oauthtokenget(myAuth.column, myAuth.code, alloc);
    }
    if (command.id == 8) { //column config changed
        const column = command.verb.column;
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
        warn("byebye...\n", .{});
        std.posix.exit(0);
    }
}

fn heartback(command: *thread.Command) void {
    warn("heartback() on tid {} received {}\n", .{ thread.self(), command.verb });
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
        warn("column {s} in {s} Ignoring request.\n", .{ column.makeTitle(), if (column.inError) @as([]const u8, "error!") else @as([]const u8, "progress.") });
    } else {
        warn("column http get {s}\n", .{column.makeTitle()});
        column.refreshing = true;
        columnget(column, allocator);
    }
}
