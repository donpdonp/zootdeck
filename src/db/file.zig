const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const cache_dir = "./cache";

pub fn init(allocator: *Allocator) !void {
  std.fs.makeDir(cache_dir) catch |err| {
    if(err != error.PathAlreadyExists) return err;
  };
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: *Allocator) !void {
  var dirpath = try std.fmt.allocPrint(allocator, "{}/{}", cache_dir, namespace);
  std.fs.makeDir(dirpath) catch { };
  var keypath = try std.fmt.allocPrint(allocator, "{}/{}", dirpath, key);
  if (std.fs.File.openWrite(keypath)) |*file| {
    try file.write(value);
    file.close();
  } else |err| {
    warn("open write err {} {}\n", keypath, err);
  }
}
