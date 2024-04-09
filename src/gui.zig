// gui.zig
const std = @import("std");
const util = @import("./util.zig");
const warn = util.log;
const Allocator = std.mem.Allocator;

const config = @import("./config.zig");
const toot_lib = @import("./toot.zig");
const thread = @import("./thread.zig");

const guilib = @import("./gui/gtk3.zig");

const GUIError = error{Init};
const Column = guilib.Column;
var columns: std.ArrayList(*Column) = undefined;
var allocator: Allocator = undefined;
var settings: *config.Settings = undefined;

pub fn init(alloca: Allocator, set: *config.Settings) !void {
    warn("GUI init()", .{});
    settings = set;
    allocator = alloca;
    columns = std.ArrayList(*Column).init(allocator);
    try guilib.init(alloca, set);
}

var myActor: *thread.Actor = undefined;
var stop = false;

pub fn go(data: ?*anyopaque) callconv(.C) ?*anyopaque {
    warn("GUI {s} mainloop thread.self()={}\n", .{ guilib.libname(), thread.self() });
    myActor = @as(*thread.Actor, @ptrCast(@alignCast(data)));
    if (guilib.gui_setup(myActor)) {
        // mainloop
        var then = std.time.milliTimestamp();
        while (!stop) {
            stop = guilib.mainloop();
            var now = std.time.milliTimestamp();
            //warn("{}ms pause gui mainloop\n", .{now - then});
            then = now;
        }
        warn("final mainloop {}\n", .{guilib.mainloop()});
        guilib.gui_end();
    } else |err| {
        warn("gui error {}\n", .{err});
    }
    return null;
}
pub fn schedule(func: ?*const fn (?*anyopaque) callconv(.C) c_int, param: ?*anyopaque) void {
    guilib.schedule(func, param);
}

pub fn show_main_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.show_main_schedule(in);
}

pub fn add_column_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.add_column_schedule(in);
}

pub fn column_remove_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.column_remove_schedule(in);
}

pub fn column_config_oauth_url_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.column_config_oauth_url_schedule(in);
}

pub fn update_column_config_oauth_finalize_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.update_column_config_oauth_finalize_schedule(in);
}

pub fn update_column_ui_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.update_column_ui_schedule(in);
}

pub fn update_column_netstatus_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.update_column_netstatus_schedule(in);
}

pub fn update_column_toots_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.update_column_toots_schedule(in);
}

pub fn update_author_photo_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.update_author_photo_schedule(in);
}

pub const TootPic = guilib.TootPic;
pub fn toot_media_schedule(in: ?*anyopaque) callconv(.C) c_int {
    return guilib.toot_media_schedule(in);
}
