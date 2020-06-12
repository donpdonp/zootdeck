// GTK+
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const thread = @import("../thread.zig");

const c = @cImport({
    @cInclude("QtWidgets/qapplication.h");
});

const GUIError = error{ Init, Setup };
var myActor: *thread.Actor = undefined;
var app = c.qApp;

pub const Column = struct {
//  builder: [*c]c.GtkBuilder,
//  columnbox: [*c]c.GtkWidget,
//  config_window: [*c]c.GtkWidget,
    main: *config.ColumnInfo
};

pub fn libname() []const u8 {
    return "qt5";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
    var tf = usize(1);
    if (tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
    myActor = actor;
    c.qApp();
    return GUIError.Setup;
}

pub fn mainloop() void {}

pub fn gui_end() void {
    warn("gui ended\n");
}

pub fn schedule(func: ?fn (*c_void) callconv(.C) c_int, param: *c_void) void {}

pub fn show_main_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn add_column_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn column_remove_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn column_config_oauth_url_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_ui_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_netstatus_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_toots_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}
