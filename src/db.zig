// db.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("lmdb.h");
});

var env: *c.MDB_env = undefined;

pub fn init(allocator: *Allocator) !void {
  var mdb_ret: c_int = 0;
  mdb_ret = c.mdb_env_create(@ptrCast([*c]?*c.MDB_env, &env));
  if(mdb_ret != 0) {
    warn("mdb_env_create failed {}\n", mdb_ret);
    return error.BadValue;
  }
  mdb_ret = c.mdb_env_open(env, c"db", 0, 0o644);
  if(mdb_ret != 0) {
    warn("mdb_env_open failed {}\n", mdb_ret);
    return error.BadValue;
  }
}

pub fn has(key: []const u8) bool {
  return false;
}

pub fn get(key: []u8) []u8 {
}