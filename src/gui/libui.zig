// libui.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const thread = @import("../thread.zig");
const config = @import("../config.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("ui.h");
});

const GUIError = error{ Init, Setup };
var columnbox: *c.uiBox = undefined;

pub const Column = struct {
    columnbox: [*c]c.uiControl,
    //  config_window: [*c]c.GtkWidget,
    main: *config.ColumnInfo,
};

var myActor: *thread.Actor = undefined;

pub fn libname() []const u8 {
    return "libui";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
    var tf = usize(1);
    if (tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
    myActor = actor;
    var uiInitOptions = c.uiInitOptions{ .Size = 0 };
    var err = c.uiInit(&uiInitOptions);

    if (err == 0) {
        build();
    } else {
        warn("libui init failed {}\n", err);
        return GUIError.Init;
    }
}

fn build() void {
    var window = c.uiNewWindow("Zootdeck", 320, 240, 0);
    c.uiWindowSetMargined(window, 1);
    const f: ?fn (*c.uiWindow, *anyopaque) callconv(.C) c_int = onClosing;
    c.uiWindowOnClosing(window, f, null);

    var hbox = c.uiNewHorizontalBox();
    c.uiWindowSetChild(window, @ptrCast(*c.uiControl, @alignCast(8, hbox)));
    //columnbox = @ptrCast(*c.uiControl, @alignCast(8, hbox));
    if (hbox) |hb| {
        columnbox = hb;
    }

    var controls_vbox = c.uiNewVerticalBox();
    c.uiBoxAppend(hbox, @ptrCast(*c.uiControl, @alignCast(8, controls_vbox)), 0);

    var addButton = c.uiNewButton("+");
    c.uiBoxAppend(controls_vbox, @ptrCast(*c.uiControl, @alignCast(8, addButton)), 0);

    c.uiControlShow(@ptrCast(*c.uiControl, @alignCast(8, window)));
}

pub fn mainloop() void {
    c.uiMain();
}

pub fn gui_end() void {}

export fn onClosing(w: *c.uiWindow, data: *anyopaque) c_int {
    warn("ui quitting\n");
    c.uiQuit();
    return 1;
}

pub fn schedule(funcMaybe: ?fn (*anyopaque) callconv(.C) c_int, param: *anyopaque) void {
    if (funcMaybe) |func| {
        warn("schedule FUNC {}\n", func);
        _ = func(@ptrCast(*anyopaque, &"w"));
    }
}

pub fn show_main_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn add_column_schedule(in: *anyopaque) callconv(.C) c_int {
    warn("libui add column\n");
    var column_vbox = c.uiNewVerticalBox(); // crashes here
    var url_label = c.uiNewLabel("site.xyz");
    c.uiBoxAppend(column_vbox, @ptrCast(*c.uiControl, @alignCast(8, url_label)), 0);

    c.uiBoxAppend(columnbox, @ptrCast(*c.uiControl, @alignCast(8, column_vbox)), 0);
    return 0;
}

pub fn column_remove_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn column_config_oauth_url_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn update_column_ui_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn update_column_netstatus_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}

pub fn update_column_toots_schedule(in: *anyopaque) callconv(.C) c_int {
    return 0;
}
