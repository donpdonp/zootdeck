// GTK+
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const config = @import("../config.zig");
const toot_lib = @import("../toot.zig");

const c = @cImport({
  @cInclude("qt5/QtWidgets/qapplication.h");
});

const GUIError = error{QtInit};

var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;
var columns:std.ArrayList(*Column) = undefined;

pub const Column = struct {
//  builder: [*c]c.GtkBuilder,
//  columnbox: [*c]c.GtkWidget,
//  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo
};

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  settings = set;
  allocator = alloca;
  columns = std.ArrayList(*Column).init(allocator);
  var tf = usize(1);
  if(tf != 1) return GUIError.QtInit;
}
