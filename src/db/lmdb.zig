// db.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const util = @import("../util.zig");
const warn = util.log;

const c = @cImport({
    @cInclude("lmdb.h");
});

var env: *c.MDB_env = undefined;
const dbpath = "./db";

pub fn init(allocator: Allocator) !void {
    var mdb_ret: c_int = 0;
    mdb_ret = c.mdb_env_create(@as([*c]?*c.MDB_env, @ptrCast(&env)));
    if (mdb_ret != 0) {
        warn("mdb_env_create failed {}\n", .{mdb_ret});
        return error.BadValue;
    }
    mdb_ret = c.mdb_env_set_mapsize(env, 250 * 1024 * 1024);
    if (mdb_ret != 0) {
        warn("mdb_env_set_mapsize failed {}\n", .{mdb_ret});
        return error.BadValue;
    }
    std.posix.mkdir(dbpath, 0o0755) catch {};
    mdb_ret = c.mdb_env_open(env, util.sliceToCstr(allocator, dbpath), 0, 0o644);
    if (mdb_ret != 0) {
        warn("mdb_env_open failed {}\n", .{mdb_ret});
        return error.BadValue;
    }
    stats();
}

pub fn stats() void {
    var mdbStat: c.MDB_stat = undefined;
    _ = c.mdb_env_stat(env, &mdbStat);
    util.log("lmdb cache {} entries", .{mdbStat.ms_entries});
}

pub fn txn_open() !?*c.MDB_txn {
    var txn: ?*c.MDB_txn = undefined;
    const ret = c.mdb_txn_begin(env, null, 0, &txn);
    if (ret == 0) {
        return txn;
    } else {
        warn("mdb_txn_begin ERR {}", .{ret});
        return error.mdb_txn_begin;
    }
}

pub fn dbi_open(txn: ?*c.struct_MDB_txn) !c.MDB_dbi {
    var dbi_ptr: c.MDB_dbi = 0;
    const ret = c.mdb_dbi_open(txn, null, c.MDB_CREATE, @ptrCast(&dbi_ptr));
    if (ret == 0) {
        return dbi_ptr;
    } else {
        warn("mdb_dbi_open ERR {}", .{ret});
        return error.mdb_dbi_open;
    }
}

pub fn csr_open(txn: ?*c.struct_MDB_txn, dbi: c.MDB_dbi) !?*c.MDB_cursor {
    var csr_ptr: ?*c.MDB_cursor = undefined;
    const ret = c.mdb_cursor_open(txn, dbi, &csr_ptr);
    if (ret == 0) {
        return csr_ptr;
    } else {
        warn("mdb_dbi_open ERR {}", .{ret});
        return error.mdb_dbi_open;
    }
}

pub fn scan(namespaces: []const []const u8, allocator: Allocator) ![]const []const u8 {
    const txn = try txn_open();
    const dbi = try dbi_open(txn);
    const csr = try csr_open(txn, dbi);

    const fullkey = util.strings_join_separator(namespaces, ':', allocator);
    const mdb_key = mdbVal(fullkey, allocator);
    const mdb_value = mdbVal("", allocator);
    const ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_NEXT);
    if (ret == 0) {
        warn("lmdb.scan {s} key{} val{}", .{ fullkey, mdb_key.mv_size, mdb_value.mv_size });
    }
    return &.{};
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: Allocator) !void {
    warn("lmdb write {s} {s}={s}", .{ namespace, key, value });
    const txn = try txn_open();
    const dbi = try dbi_open(txn);
    // TODO: seperator issue. perhaps 2 byte invalid utf8 sequence
    const fullkey = util.strings_join_separator(&.{ namespace, key }, ':', allocator);
    const mdb_key = mdbVal(fullkey, allocator);
    const mdb_value = mdbVal(value, allocator);
    var ret = c.mdb_put(txn, dbi, mdb_key, mdb_value, 0);
    if (ret == 0) {
        ret = c.mdb_txn_commit(txn);
        if (ret == 0) {
            _ = c.mdb_dbi_close(env, dbi);
        } else {
            warn("mdb_txn_commit ERR {}", .{ret});
            return error.mdb_txn_commit;
        }
    } else {
        warn("mdb_put ERR {}\n", .{ret});
        return error.mdb_put;
    }
}

fn mdbVal(data: []const u8, allocator: Allocator) *c.MDB_val {
    const dataptr = @as(?*anyopaque, @ptrFromInt(@intFromPtr(data.ptr)));
    var mdb_val = allocator.create(c.MDB_val) catch unreachable;
    mdb_val.mv_size = data.len;
    mdb_val.mv_data = dataptr;
    return mdb_val;
}
