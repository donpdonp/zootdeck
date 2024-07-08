// db.zig
const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
const util = @import("../util.zig");

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
    std.os.mkdir(dbpath, 0o0755) catch {};
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
    warn("lmdb cache {} entries\n", .{mdbStat.ms_entries});
}

pub fn write(namespace: []const u8, key: []const u8, value: []const u8, allocator: Allocator) !void {
    var txnptr = allocator.create(*c.struct_MDB_txn) catch unreachable;
    var ctxnMaybe = @as([*c]?*c.struct_MDB_txn, @ptrCast(txnptr));
    var ret = c.mdb_txn_begin(env, null, 0, ctxnMaybe);
    if (ret == 0) {
        //    warn("lmdb write {} {}={}\n", namespace, key, value);
        var dbiptr = allocator.create(c.MDB_dbi) catch unreachable;
        ret = c.mdb_dbi_open(txnptr.*, null, c.MDB_CREATE, dbiptr);
        if (ret == 0) {
            // TODO: seperator issue. perhaps 2 byte invalid utf8 sequence
            var fullkey = "Z";
            _ = key;
            _ = namespace;
            //std.fmt.allocPrint(allocator, "{s}:{s}", .{ namespace, key }) catch unreachable;
            var mdb_key = mdbVal(fullkey, allocator);
            var mdb_value = mdbVal(value, allocator);
            ret = c.mdb_put(txnptr.*, dbiptr.*, mdb_key, mdb_value, 0);
            if (ret == 0) {
                ret = c.mdb_txn_commit(txnptr.*);
                if (ret == 0) {
                    _ = c.mdb_dbi_close(env, dbiptr.*);
                } else {
                    warn("mdb_txn_commit ERR {}\n", .{ret});
                    return error.mdb_txn_commit;
                }
            } else {
                warn("mdb_put ERR {}\n", .{ret});
                return error.mdb_put;
            }
        } else {
            warn("mdb_dbi_open ERR {}\n", .{ret});
            return error.mdb_dbi_open;
        }
    } else {
        warn("mdb_txn_begin ERR {}\n", .{ret});
        return error.mdb_txn_begin;
    }
}

fn mdbVal(data: []const u8, allocator: Allocator) *c.MDB_val {
    var dataptr = @as(?*anyopaque, @ptrFromInt(@intFromPtr(data.ptr)));
    var mdb_val = allocator.create(c.MDB_val) catch unreachable;
    mdb_val.mv_size = data.len;
    mdb_val.mv_data = dataptr;
    return mdb_val;
}
