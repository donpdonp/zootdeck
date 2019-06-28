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
  const buf = try allocator.alloc(u8, cache_dir.len + namespace.len + 1);
  var dir = try std.fmt.bufPrint(buf, "{}/{}", cache_dir, namespace);
  std.fs.makeDir(dir) catch { };
  //if (std.fs.File.openWrite(filename)) |*file| {
  //}
}
