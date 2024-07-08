const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const cache_dir = "./cache";

pub fn init() !void {
    std.posix.mkdir(cache_dir, 0o644) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

pub fn has(namespace: []const u8, key: []const u8, allocator: Allocator) bool {
    _ = cache_dir;
    _ = namespace;
    _ = key;
    _ = allocator;
    const keypath = "Z"; //std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ cache_dir, namespace, key }) catch unreachable;
    var found = false;
    if (std.fs.cwd().access(keypath, .{ .mode = .read_only })) {
        found = true;
    } else |err| {
        warn("dbfile did not find {s} {}\n", .{ keypath, err });
    }
    return found;
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: Allocator) !void {
    _ = cache_dir;
    _ = namespace;
    _ = allocator;
    const dirpath = "Z"; //try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cache_dir, namespace });
    warn("MKDIR {s}\n", .{dirpath});
    var dir = std.fs.Dir.makeOpenPath(std.fs.cwd(), dirpath, .{}) catch unreachable;
    defer dir.close();
    if (dir.createFile(key, .{ .truncate = true })) |*file| {
        _ = try file.write(value);
        file.close();
    } else |err| {
        warn("open write err {s} {s} {}\n", .{ dirpath, key, err });
    }
}
