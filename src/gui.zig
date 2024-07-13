// gui.zig
const std = @import("std");
const util = @import("./util.zig");
const warn = util.log;
const Allocator = std.mem.Allocator;

const config = @import("./config.zig");
const toot_lib = @import("./toot.zig");
const thread = @import("./thread.zig");

const GUIError = error{Init};
const Column = u32;
var columns: std.ArrayList(*Column) = undefined;
var allocator: Allocator = undefined;
var settings: *config.Settings = undefined;

pub fn init(alloca: Allocator, set: *config.Settings) !void {
    warn("GUI init()", .{});
    settings = set;
    allocator = alloca;
    columns = std.ArrayList(*Column).init(allocator);
}

var myActor: *thread.Actor = undefined;
var stop = false;

pub fn go(data: ?*anyopaque) callconv(.C) ?*anyopaque {
    warn("GUI {s} mainloop thread.self()={!}\n", .{ "none", thread.self() });
    myActor = @as(*thread.Actor, @ptrCast(@alignCast(data)));
    return null;
}
pub fn schedule(func: ?*const fn (?*anyopaque) callconv(.C) c_int, param: ?*anyopaque) void {
    _ = func;
    _ = param;
}

pub fn show_main_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn add_column_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn column_remove_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn column_config_oauth_url_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_ui_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_netstatus_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_toots_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_author_photo_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn toot_media_schedule(in: ?*anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}
