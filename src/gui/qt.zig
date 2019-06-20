// GTK+
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const c = @cImport({
  @cInclude("qt5/QtWidgets/qapplication.h");
});

const GUIError = error{QtInit};

pub const Column = struct {
//  builder: [*c]c.GtkBuilder,
//  columnbox: [*c]c.GtkWidget,
//  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo
};

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  var tf = usize(1);
  if(tf != 1) return GUIError.QtInit;
}
