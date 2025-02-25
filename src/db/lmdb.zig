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

pub fn txn_commit(txn: ?*c.MDB_txn) !void {
    const ret = c.mdb_txn_commit(txn);
    if (ret == 0) {
        return;
    } else {
        warn("mdb_txn_commit ERR {}", .{ret});
        return error.mdb_txn_commit;
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
    var answers = std.ArrayList([]const u8).init(allocator);
    const txn = try txn_open();
    const dbi = try dbi_open(txn);
    const csr = try csr_open(txn, dbi);

    const fullkey = util.strings_join_separator(namespaces, ':', allocator);
    const mdb_key = sliceToMdbVal(fullkey, allocator);
    const mdb_value = sliceToMdbVal("", allocator);
    const ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_SET_RANGE);
    const ret_key = mdbValToBytes(mdb_key);
    const ret_value = mdbValToBytes(mdb_value);
    if (ret == 0) {
        warn("lmdb.scan {s} key \"{s}\" val \"{s}\"", .{ fullkey, ret_key, ret_value });
        try answers.append(ret_value);
        while (innerScan(csr, mdb_key, allocator)) |val| {
            if (answers.items.len < 5) {
                try answers.append(val);
            }
        }
    }
    try txn_commit(txn);
    return answers.toOwnedSlice();
}

fn innerScan(csr: ?*c.MDB_cursor, mdb_key: ?*c.MDB_val, allocator: std.mem.Allocator) ?[]const u8 {
    const mdb_value = sliceToMdbVal("", allocator);
    const ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_NEXT);
    const ret_value = mdbValToBytes(mdb_value);
    if (ret == 0) {
        warn("lmdb.scan \"{s}\"", .{ret_value});
        return ret_value;
    }
    return null;
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: Allocator) !void {
    const txn = try txn_open();
    const dbi = try dbi_open(txn);
    // TODO: seperator issue. perhaps 2 byte invalid utf8 sequence
    const fullkey = util.strings_join_separator(&.{ namespace, key }, ':', allocator);
    warn("lmdb.write {s}={s}", .{ fullkey, value });
    const mdb_key = sliceToMdbVal(fullkey, allocator);
    const mdb_value = sliceToMdbVal(value, allocator);
    const ret = c.mdb_put(txn, dbi, mdb_key, mdb_value, 0);
    if (ret == 0) {
        try txn_commit(txn);
    } else {
        warn("mdb_put ERR {}\n", .{ret});
        return error.mdb_put;
    }
}

fn sliceToMdbVal(data: []const u8, allocator: Allocator) *c.MDB_val {
    var mdb_val = allocator.create(c.MDB_val) catch unreachable;
    mdb_val.mv_size = data.len;
    mdb_val.mv_data = @constCast(@ptrCast(data.ptr));
    return mdb_val;
}

fn mdbValToBytes(mdb_val: *c.MDB_val) []const u8 {
    var ret_key: []const u8 = undefined;
    ret_key.len = mdb_val.mv_size;
    ret_key.ptr = @as([*]const u8, @ptrCast(mdb_val.mv_data));
    return ret_key;
}
