const std = @import("std");
const builtin = @import("builtin");
const thread = @import("./thread.zig");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
var GPAllocator = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = GPAllocator.allocator();

const Buffers = @import("./simple_buffer.zig");

pub fn sliceAddNull(allocator: Allocator, str: []const u8) [:0]const u8 {
    return allocator.dupeZ(u8, str) catch unreachable;
}

pub fn sliceToCstr(allocator: Allocator, str: []const u8) [*:0]u8 {
    var str_null: []u8 = allocator.alloc(u8, str.len + 1) catch unreachable;
    std.mem.copy(u8, str_null[0..], str);
    str_null[str.len] = 0;
    return @ptrCast(str_null.ptr);
}

pub fn cstrToSliceCopy(allocator: Allocator, cstr: [*c]const u8) []const u8 {
    var i: usize = std.mem.len(cstr);
    var ram = allocator.alloc(u8, i) catch unreachable;
    std.mem.copy(u8, ram, cstr[0..i]);
    return ram;
}

pub fn log(comptime msg: []const u8, args: anytype) void {
    const tid = thread.self();
    const tid_name = thread.name(tid);
    //const tz = std.os.timezone.tz_minuteswest;
    var tz = std.os.timezone{ .tz_minuteswest = 0, .tz_dsttime = 0 };
    std.os.gettimeofday(null, &tz); // does not set tz
    const now_ms = std.time.milliTimestamp() + tz.tz_minuteswest * std.time.ms_per_hour;
    const esec = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(@divTrunc(now_ms, std.time.ms_per_s))) };
    const eday = esec.getEpochDay();
    const yday = eday.calculateYearDay();
    const mday = yday.calculateMonthDay();
    const dsec = esec.getDaySeconds();
    const time_str = std.fmt.allocPrint(alloc, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ yday.year, mday.month.numeric(), mday.day_index + 1, dsec.getHoursIntoDay(), dsec.getMinutesIntoHour(), dsec.getSecondsIntoMinute() });
    std.debug.print("{s}[tid#{d}/{s:9}] " ++ msg ++ "\n", .{ time_str, tid, tid_name } ++ args);
}

pub fn hashIdSame(comptime T: type, a: T, b: T) bool {
    return std.mem.eql(u8, a.get("id").?.String, b.get("id").?.String);
}

pub fn mastodonExpandUrl(host: []const u8, home: bool, allocator: Allocator) []const u8 {
    var url = Buffers.SimpleU8.initSize(allocator, 0) catch unreachable;
    var filteredHost = host;
    if (filteredHost.len > 0) {
        if (filteredHost[filteredHost.len - 1] == '/') {
            filteredHost = filteredHost[0 .. filteredHost.len - 1];
        }
        if (std.mem.order(u8, filteredHost[0..6], "https:") != std.math.Order.eq) {
            url.append("https://") catch unreachable;
        }
        url.append(filteredHost) catch unreachable;
        if (home) {
            url.append("/api/v1/timelines/home") catch unreachable;
        } else {
            url.append("/api/v1/timelines/public") catch unreachable;
        }
        return url.toSliceConst();
    } else {
        warn("mastodonExpandUrl given empty host!\n", .{});
        return "";
    }
}

pub fn htmlTagStrip(str: []const u8, allocator: Allocator) ![]const u8 {
    var newStr = try Buffers.SimpleU8.initSize(allocator, 0);
    const States = enum { Looking, TagBegin };
    var state = States.Looking;
    var tagEndPlusOne: usize = 0;
    for (str, 0..) |char, idx| {
        if (state == States.Looking and char == '<') {
            state = States.TagBegin;
            try newStr.append(str[tagEndPlusOne..idx]);
        } else if (state == States.TagBegin and char == '>') {
            tagEndPlusOne = idx + 1;
            state = States.Looking;
        }
    }
    if (tagEndPlusOne <= str.len) {
        try newStr.append(str[tagEndPlusOne..]);
    }
    return newStr.toSliceConst();
}

test "htmlTagStrip" {
    const allocator = std.debug.global_allocator;
    var stripped = htmlTagStrip("a<p>b</p>", allocator) catch unreachable;
    std.testing.expect(std.mem.eql(u8, stripped, "ab"));
    stripped = htmlTagStrip("a<p>b</p>c", allocator) catch unreachable;
    std.testing.expect(std.mem.eql(u8, stripped, "abc"));
    stripped = htmlTagStrip("a<a img=\"\">b</a>c", allocator) catch unreachable;
    std.testing.expect(std.mem.eql(u8, stripped, "abc"));
}

pub fn htmlEntityDecode(str: []const u8, allocator: Allocator) ![]const u8 {
    var newStr = try Buffers.SimpleU8.initSize(allocator, 0);
    var previousStrEndMark: usize = 0;
    const States = enum { Looking, EntityBegin, EntityFound };
    var state = States.Looking;
    var escStart: usize = undefined;
    for (str, 0..) |char, idx| {
        if (state == States.Looking and char == '&') {
            state = States.EntityBegin;
            escStart = idx;
        } else if (state == States.EntityBegin) {
            if (char == ';') {
                const snip = str[previousStrEndMark..escStart];
                previousStrEndMark = idx + 1;
                try newStr.append(snip);
                const sigil = str[escStart + 1 .. idx];
                var newChar: u8 = undefined;
                if (std.mem.order(u8, sigil, "amp") == std.math.Order.eq) {
                    newChar = '&';
                }
                try newStr.appendByte(newChar);
                state = States.Looking;
            } else if (idx - escStart > 4) {
                state = States.Looking;
            }
        }
    }
    if (previousStrEndMark <= str.len) {
        try newStr.append(str[previousStrEndMark..]);
    }
    return newStr.toSliceConst();
}

test "htmlEntityParse" {
    const allocator = std.debug.global_allocator;
    var stripped = htmlEntityDecode("amp&amp;pam", allocator) catch unreachable;
    std.testing.expect(std.mem.eql(u8, stripped, "amp&pam"));
}
