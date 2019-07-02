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
//const dbs = std.hash_map.AutoHashMap([]const u8, *c.MDB_dbi);

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
  stats();
}

pub fn stats() void {
  var mdbStat: c.MDB_stat = undefined;
  var ret = c.mdb_env_stat(env, &mdbStat);
  warn("lmdb cache {} entries\n", mdbStat.ms_entries);
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: *Allocator) !void {
  var txnptr = allocator.create(*c.struct_MDB_txn) catch unreachable;
  var ctxnMaybe: [*c]?*c.struct_MDB_txn = @ptrCast([*c]?*c.struct_MDB_txn, txnptr);
  var ret = c.mdb_txn_begin(env, null, 0, ctxnMaybe);
  if (ret != 0) {
    return error.lmdb;
  }
  warn("lmdb write {} {}={}\n", namespace, key, value);
  var dbiptr = allocator.create(c.MDB_dbi) catch unreachable;
  ret = c.mdb_dbi_open(txnptr.*, util.sliceToCstr(allocator, namespace), c.MDB_CREATE, dbiptr.*);
  var keyptr = @intToPtr(?*c_void, @ptrToInt(key.ptr));
  var mdbValKey = c.MDB_val{.mv_size = key.len, .mv_data = keyptr};
  var valueptr = @intToPtr(?*c_void, @ptrToInt(value.ptr));
  var mdbValVal = c.MDB_val{.mv_size = value.len, .mv_data = valueptr};
  ret = c.mdb_put(txnptr.*, dbiptr.*, &mdbValKey, &mdbValVal, 0);
  ret = c.mdb_txn_commit(txnptr.*);
  if (ret != 0) {
    return error.lmdb;
  } else {
    warn("mdb txn COMMIT!\n");
    _ = c.mdb_dbi_close(env, dbiptr.*);
  }
  var zigfool=false;
  if(zigfool) return error.shutup;
}
