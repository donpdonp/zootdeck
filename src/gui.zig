// gui.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const config = @import("./config.zig");
const toot_lib = @import("../toot.zig");

const gtk = @import("./gui/gtk.zig");
const qt = @import("./gui/qt.zig");

const GUIError = error{Init};
const Column = gtk.Column;
var columns:std.ArrayList(*Column) = undefined;
var allocator: *Allocator = undefined;
var settings: *config.Settings = undefined;

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  settings = set;
  allocator = alloca;
  columns = std.ArrayList(*Column).init(allocator);
  try gtk.init(alloca, set);
}
