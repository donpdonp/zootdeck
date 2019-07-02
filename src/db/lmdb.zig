// db.zig
const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;
const util = @import("../util.zig");

const c = @cImport({
    @cInclude("lmdb.h");
});

var env: *c.MDB_env = undefined;
const dbpath = "./db";

pub fn init(allocator: *Allocator) !void {
  var mdb_ret: c_int = 0;
  mdb_ret = c.mdb_env_create(@ptrCast([*c]?*c.MDB_env, &env));
  if(mdb_ret != 0) {
    warn("mdb_env_create failed {}\n", mdb_ret);
    return error.BadValue;
  }
  std.fs.makeDir(dbpath) catch { };
  mdb_ret = c.mdb_env_open(env, util.sliceToCstr(allocator, dbpath), 0, 0o644);
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

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: *Allocator) !void {
  var txnptr = allocator.create(*c.struct_MDB_txn) catch unreachable;
  var ctxnMaybe: [*c]?*c.struct_MDB_txn = @ptrCast([*c]?*c.struct_MDB_txn, txnptr);
  var ret = c.mdb_txn_begin(env, null, 0, ctxnMaybe);
  if (ret != 0) {
    return error.lmdb;
  }
  if(ctxnMaybe) |txn| {
    warn("lmdb write {} {} {}\n", namespace, key, value);
    ret = c.mdb_txn_commit(txn.*);
    if (ret != 0) {
      return error.lmdb;
    }
  }
  var zigfool=false;
  if(zigfool) return error.shutup;
}
