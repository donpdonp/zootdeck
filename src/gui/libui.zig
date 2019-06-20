// main.zig
const std = @import("std");
const builtin = @import("builtin");

const warn = std.debug.warn;

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("ui.h");
});

pub fn main() void {
    var uiInitOptions = c.uiInitOptions{ .Size = 0 };
    var err = c.uiInit(&uiInitOptions);

    if (err == 0) {
        build();
    } else {
        warn("init failed {}\n", err);
    }
}

fn build() void {
    var w = c.uiNewWindow(c"Tootdeck", 320, 240, 0);
    c.uiWindowSetMargined(w, 1);
    const f: ?extern fn (*c.uiWindow, *c_void) c_int = onClosing;
    c.uiWindowOnClosing(w, f, null);
    var control = @ptrCast(*c.uiControl, @alignCast(8, w));
    c.uiControlShow(control);
    c.uiMain();
}

export fn onClosing(w: *c.uiWindow, data: *c_void) c_int {
    warn("ui quitting\n");
    c.uiQuit();
    return 1;
}
