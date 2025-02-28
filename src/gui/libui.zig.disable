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

pub fn init(allocator: *Allocator, set: *config.Settings) !void {
    _ = allocator;
    _ = set;
    const tf = usize(1);
    if (tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
    myActor = actor;
    var uiInitOptions = c.uiInitOptions{ .Size = 0 };
    const err = c.uiInit(&uiInitOptions);

    if (err == 0) {
        build();
    } else {
        warn("libui init failed {!}\n", err);
        return GUIError.Init;
    }
}

fn build() void {
    const window = c.uiNewWindow("Zootdeck", 320, 240, 0);
    c.uiWindowSetMargined(window, 1);
    const f: ?fn (*c.uiWindow, *anyopaque) callconv(.C) c_int = onClosing;
    c.uiWindowOnClosing(window, f, null);

    const hbox = c.uiNewHorizontalBox();
    c.uiWindowSetChild(window, @as(*c.uiControl, @ptrCast(@alignCast(hbox))));
    //columnbox = @ptrCast(*c.uiControl, @alignCast(8, hbox));
    if (hbox) |hb| {
        columnbox = hb;
    }

    const controls_vbox = c.uiNewVerticalBox();
    c.uiBoxAppend(hbox, @as(*c.uiControl, @ptrCast(@alignCast(controls_vbox))), 0);

    const addButton = c.uiNewButton("+");
    c.uiBoxAppend(controls_vbox, @as(*c.uiControl, @ptrCast(@alignCast(addButton))), 0);

    c.uiControlShow(@as(*c.uiControl, @ptrCast(@alignCast(window))));
}

pub fn mainloop() void {
    c.uiMain();
}

pub fn gui_end() void {}

export fn onClosing(w: *c.uiWindow, data: *anyopaque) c_int {
    _ = w;
    _ = data;
    warn("ui quitting\n");
    c.uiQuit();
    return 1;
}

pub fn schedule(funcMaybe: ?fn (*anyopaque) callconv(.C) c_int, param: *anyopaque) void {
    _ = param;
    if (funcMaybe) |func| {
        warn("schedule FUNC {}\n", func);
        _ = func(@as(*anyopaque, @ptrCast(&"w")));
    }
}

pub fn show_main_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn add_column_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    warn("libui add column\n");
    const column_vbox = c.uiNewVerticalBox(); // crashes here
    const url_label = c.uiNewLabel("site.xyz");
    c.uiBoxAppend(column_vbox, @as(*c.uiControl, @ptrCast(@alignCast(url_label))), 0);

    c.uiBoxAppend(columnbox, @as(*c.uiControl, @ptrCast(@alignCast(column_vbox))), 0);
    return 0;
}

pub fn column_remove_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn column_config_oauth_url_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_ui_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_netstatus_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}

pub fn update_column_toots_schedule(in: *anyopaque) callconv(.C) c_int {
    _ = in;
    return 0;
}
