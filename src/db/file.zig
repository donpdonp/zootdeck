const std = @import("std");
const builtin = @import("builtin");
const util = @import("../util.zig");
const warn = util.log;
const Allocator = std.mem.Allocator;

const cache_dir = "./cache";

pub fn init(alloc: Allocator) !void {
    const cwd = std.fs.cwd();
    const cwd_path = std.fs.Dir.realpathAlloc(cwd, alloc, ".") catch unreachable;
    const parts: []const []const u8 = &[_][]const u8{ cwd_path, cache_dir };
    const cache_path = std.fs.path.join(alloc, parts) catch unreachable;
    std.posix.mkdir(cache_path, 0o755) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    warn("cache dir {s}", .{cache_path});
}

pub fn has(namespace: []const u8, key: []const u8, allocator: Allocator) bool {
    const keypath = std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ cache_dir, namespace, key }) catch unreachable;
    var found = false;
    if (std.fs.cwd().access(keypath, .{ .mode = .read_only })) {
        found = true;
    } else |err| {
        warn("dbfile did not find {s} {!}", .{ keypath, err });
    }
    return found;
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: Allocator) !void {
    const dirpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cache_dir, namespace });
    warn("mkdir {s}", .{dirpath});
    var dir = std.fs.Dir.makeOpenPath(std.fs.cwd(), dirpath, .{}) catch unreachable;
    defer dir.close();
    if (dir.createFile(key, .{ .truncate = true })) |*file| {
        _ = try file.write(value);
        file.close();
    } else |err| {
        warn("open write err {s} {s} {any}", .{ dirpath, key, err });
    }
}
