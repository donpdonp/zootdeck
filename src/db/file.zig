const std = @import("std");
const builtin = @import("builtin");
const util = @import("../util.zig");
const warn = util.log;
const Allocator = std.mem.Allocator;

const cache_dir_name = "cache";
var cache_path: []const u8 = undefined;

pub fn init(alloc: Allocator) !void {
    const cwd = std.fs.cwd();
    const cwd_path = std.fs.Dir.realpathAlloc(cwd, alloc, ".") catch unreachable;
    const parts: []const []const u8 = &[_][]const u8{ cwd_path, cache_dir_name };
    cache_path = std.fs.path.join(alloc, parts) catch unreachable;
    std.posix.mkdir(cache_path, 0o755) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    warn("cache dir {s}", .{cache_path});
}

pub fn has(namespaces: []const []const u8, key: []const u8, allocator: Allocator) bool {
    var namespace_paths = std.ArrayList([]const u8).init(allocator);
    namespace_paths.append(cache_path) catch unreachable;
    namespace_paths.appendSlice(namespaces) catch unreachable;
    namespace_paths.append(key) catch unreachable;
    const keypath = std.fs.path.join(allocator, namespace_paths.items) catch unreachable;
    var found = false;
    if (std.fs.cwd().access(keypath, .{ .mode = .read_only })) {
        warn("db_file.has found {s}", .{keypath});
        found = true;
    } else |err| {
        warn("db_file.has did not find {s} {!}", .{ keypath, err });
    }
    return found;
}

pub fn read(namespaces: []const []const u8, allocator: Allocator) ![]const u8 {
    var namespace_paths: std.ArrayList([]const u8) = .{};
    namespace_paths.append(allocator, cache_path) catch unreachable;
    namespace_paths.appendSlice(allocator, namespaces) catch unreachable;
    const filename = std.fs.path.join(allocator, namespace_paths.items) catch unreachable;
    warn("db_file.read {s}", .{filename});
    return try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
}

pub fn write(namespaces: []const []const u8, key: []const u8, value: []const u8, allocator: Allocator) ![]const u8 {
    const namespace = std.fs.path.join(allocator, namespaces) catch unreachable;
    const cache_dir = std.fs.openDirAbsolute(cache_path, .{ .access_sub_paths = true }) catch unreachable;
    std.fs.Dir.makePath(cache_dir, namespace) catch unreachable;

    var namespace_paths = std.ArrayList([]const u8).init(allocator);
    namespace_paths.append(cache_path) catch unreachable;
    namespace_paths.appendSlice(namespaces) catch unreachable;
    const dirpath = std.fs.path.join(allocator, namespace_paths.items) catch unreachable;
    var dir = std.fs.Dir.makeOpenPath(std.fs.cwd(), dirpath, .{}) catch unreachable;
    defer dir.close();
    if (dir.createFile(key, .{ .truncate = true })) |*file| {
        _ = try file.write(value);
        file.close();
        warn("db_file.wrote {s}/{s}", .{ dirpath, key });
        const filename = std.fs.path.join(allocator, &.{ dirpath, key }) catch unreachable;
        return filename;
    } else |err| {
        warn("db_file.write( {s} {s} ) {any}", .{ dirpath, key, err });
        return err;
    }
}
