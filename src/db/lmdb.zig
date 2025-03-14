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

pub const Key = struct {
    parts: []const []const u8,

    const This = @This();
    const Separator = ':';

    pub fn init(parts: []const []const u8) This {
        return .{ .parts = parts };
    }

    pub fn toString(self: *const This, allocator: Allocator) []const u8 {
        return util.strings_join_separator(self.parts, Separator, allocator);
    }

    pub fn lessLevel(self: *const This) Key {
        const less_level = self.parts[0 .. self.parts.len - 1];
        return This.init(less_level);
    }
};

pub fn scan(key: Key, descending: bool, allocator: Allocator) ![]const []const u8 {
    var answers = std.ArrayList([]const u8).init(allocator);
    const txn = try txn_open();
    const dbi = try dbi_open(txn);
    const csr = try csr_open(txn, dbi);
    try scanInner(csr, &answers, key, descending, allocator);
    try txn_commit(txn);
    warn("scan returning {} answers", .{answers.items.len});
    return answers.toOwnedSlice();
}

fn scanInner(csr: ?*c.MDB_cursor, answers: *std.ArrayList([]const u8), key: Key, descending: bool, allocator: Allocator) !void {
    warn("lmdb.scanInner {s} {}", .{ key.toString(allocator), descending });
    const fullkey = key.toString(allocator);
    const mdb_key = sliceToMdbVal(fullkey, allocator);
    const mdb_value = sliceToMdbVal("", allocator);
    var ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_SET_RANGE);
    var ret_key = mdbValToBytes(mdb_key);
    var ret_value = mdbValToBytes(mdb_value);
    if (ret == c.MDB_NOTFOUND) {
        warn("lmdb.scanInner cursor_get first_fail {s} set_range err#{}", .{ fullkey, ret });
        ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_LAST);
        if (ret != 0) {
            warn("lmdb.scanInner first last fail {}", .{ret});
        }
        ret_key = mdbValToBytes(mdb_key);
        ret_value = mdbValToBytes(mdb_value);
        warn("lmdb.scanInner cursor_get_last {s} {s} key \"{s}\" val \"{s}\"", .{ if (descending) "descending" else "ascending", fullkey, ret_key, ret_value });
    } else {
        warn("lmdb.scanInner cursor_set_range {s} {s} key \"{s}\" val \"{s}\"", .{ if (descending) "descending" else "ascending", fullkey, ret_key, ret_value });
        if (descending) {
            ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, c.MDB_PREV);
            if (ret != 0) {
                warn("lmdb.scanInner first prev fail {}", .{ret});
            }
            ret_key = mdbValToBytes(mdb_key);
            ret_value = mdbValToBytes(mdb_value);
            warn("lmdb.scanInner first prev {s} {s} key \"{s}\" val \"{s}\"", .{ if (descending) "descending" else "ascending", fullkey, ret_key, ret_value });
        }
    }
    while (ret == 0 and prefix_match(key.lessLevel(), ret_key, allocator)) {
        if (answers.items.len < 10) {
            try answers.append(ret_value);
        } else break;
        ret = c.mdb_cursor_get(csr, mdb_key, mdb_value, if (descending) c.MDB_PREV else c.MDB_NEXT);
        ret_value = mdbValToBytes(mdb_value);
        ret_key = mdbValToBytes(mdb_key);
        warn("lmdb.scanInner {s} {s} key \"{s}\" val \"{s}\" {} answers", .{ if (descending) "descending" else "ascending", fullkey, ret_key, ret_value, answers.items.len });
    }
}

test scan {
    try init(std.testing.allocator);
    try std.testing.expect(true);
}

fn prefix_match(key: Key, body: []const u8, allocator: Allocator) bool {
    return std.mem.startsWith(u8, body, key.toString(allocator));
}

test prefix_match {
    try std.testing.expect(prefix_match(&.{"A"}, "AB", std.testing.allocator));
    try std.testing.expect(prefix_match(&.{"A:"}, "A:", std.testing.allocator));
    try std.testing.expect(prefix_match(&.{""}, "A:", std.testing.allocator));
    try std.testing.expect(!prefix_match(&.{"B"}, "AB", std.testing.allocator));
    try std.testing.expect(!prefix_match(&.{"BB"}, "B", std.testing.allocator));
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
