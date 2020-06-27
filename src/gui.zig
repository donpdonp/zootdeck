// gui.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const config = @import("./config.zig");
const toot_lib = @import("./toot.zig");
const thread = @import("./thread.zig");

const guilib = @import("./gui/gtk.zig");

const GUIError = error{Init};
const Column = guilib.Column;
var columns: std.ArrayList(*Column) = undefined;
var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
    settings = set;
    allocator = alloca;
    columns = std.ArrayList(*Column).init(allocator);
    try guilib.init(alloca, set);
}

var myActor: *thread.Actor = undefined;
var stop = false;

pub fn go(data: ?*c_void) callconv(.C) ?*c_void {
    var data8 = @alignCast(@alignOf(thread.Actor), data);
    myActor = @ptrCast(*thread.Actor, data8);
    warn("gui {} thread start {*} {}\n", .{ guilib.libname(), myActor, myActor });
    if (guilib.gui_setup(myActor)) {
        // mainloop
        while (!stop) {
            guilib.mainloop();
        }
        guilib.gui_end();
    } else |err| {
        warn("gui error {}\n", .{err});
    }
    return null;
}

pub fn schedule(func: ?fn (?*c_void) callconv(.C) c_int, param: ?*c_void) void {
    guilib.schedule(func, param);
}

pub fn show_main_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.show_main_schedule(in);
}

pub fn add_column_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.add_column_schedule(in);
}

pub fn column_remove_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.column_remove_schedule(in);
}

pub fn column_config_oauth_url_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.column_config_oauth_url_schedule(in);
}

pub fn update_column_config_oauth_finalize_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.update_column_config_oauth_finalize_schedule(in);
}

pub fn update_column_ui_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.update_column_ui_schedule(in);
}

pub fn update_column_netstatus_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.update_column_netstatus_schedule(in);
}

pub fn update_column_toots_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.update_column_toots_schedule(in);
}

pub fn update_author_photo_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.update_author_photo_schedule(in);
}

pub const TootPic = guilib.TootPic;
pub fn toot_media_schedule(in: ?*c_void) callconv(.C) c_int {
    return guilib.toot_media_schedule(in);
}
