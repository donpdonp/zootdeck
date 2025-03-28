const std = @import("std");
const builtin = @import("builtin");
const thread = @import("./thread.zig");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
var GPAllocator = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = GPAllocator.allocator();

const SimpleBuffer = @import("./simple_buffer.zig");

pub fn sliceAddNull(allocator: Allocator, str: []const u8) []const u8 {
    return allocator.dupeZ(u8, str) catch unreachable;
}

pub fn sliceToCstr(allocator: Allocator, str: []const u8) [*]u8 {
    var str_null: []u8 = allocator.alloc(u8, str.len + 1) catch unreachable;
    std.mem.copyForwards(u8, str_null[0..], str);
    str_null[str.len] = 0;
    return str_null.ptr;
}

pub fn cstrToSliceCopy(allocator: Allocator, cstr: [*c]const u8) []const u8 {
    const i: usize = std.mem.len(cstr);
    const ram = allocator.alloc(u8, i) catch unreachable;
    std.mem.copyForwards(u8, ram, cstr[0..i]);
    return ram;
}

pub fn json_stringify(value: anytype) []u8 {
    return std.json.stringifyAlloc(alloc, value, .{}) catch unreachable;
}

pub fn strings_join_separator(parts: []const []const u8, separator: u8, allocator: Allocator) []const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    for (parts, 0..) |part, idx| {
        // todo abort if part contains separator

        buf.appendSlice(part) catch unreachable;
        if (idx != parts.len - 1) {
            buf.append(separator) catch unreachable;
        }
    }
    return buf.toOwnedSlice() catch unreachable;
}

test strings_join_separator {
    const joined = strings_join_separator(&.{ "a", "b" }, ':', std.testing.allocator);
    try std.testing.expectEqualSlices(u8, "a:b", joined);
    std.testing.allocator.free(joined);
}

pub fn log(comptime msg: []const u8, args: anytype) void {
    const tid = thread.self();
    const tid_name = thread.name(tid);
    //const tz = std.os.timezone.tz_minuteswest;
    var tz = std.posix.timezone{ .minuteswest = 0, .dsttime = 0 };
    std.posix.gettimeofday(null, &tz); // does not set tz
    const now_ms = std.time.milliTimestamp() + tz.minuteswest * std.time.ms_per_hour;
    const ms_leftover = @abs(now_ms) % std.time.ms_per_s;
    const esec = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(@divTrunc(now_ms, std.time.ms_per_s))) };
    const eday = esec.getEpochDay();
    const yday = eday.calculateYearDay();
    const mday = yday.calculateMonthDay();
    const dsec = esec.getDaySeconds();

    const time_str = std.fmt.allocPrint(alloc, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3.3}", .{ yday.year, mday.month.numeric(), mday.day_index + 1, dsec.getHoursIntoDay(), dsec.getMinutesIntoHour(), dsec.getSecondsIntoMinute(), ms_leftover }) catch unreachable;
    std.debug.print("{s} [{s:9}] " ++ msg ++ "\n", .{ time_str, tid_name } ++ args);
}

pub fn hashIdSame(comptime T: type, a: T, b: T) bool {
    const a_id = a.get("id").?.string;
    const b_id = b.get("id").?.string;
    return std.mem.eql(u8, a_id, b_id);
}

pub fn mastodonExpandUrl(host: []const u8, home: bool, allocator: Allocator) []const u8 {
    var url = SimpleBuffer.SimpleU8.initSize(allocator, 0) catch unreachable;
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
        //warn("mastodonExpandUrl given empty host", .{});
        return "";
    }
}

test "mastodonExpandUrl" {
    const url = mastodonExpandUrl("some.masto", true, alloc);
    try std.testing.expectEqualSlices(u8, url, "https://some.masto/api/v1/timelines/home");
}

pub fn htmlTagStrip(str: []const u8, allocator: Allocator) ![]const u8 {
    var newStr = try SimpleBuffer.SimpleU8.initSize(allocator, 0);
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
    var stripped = htmlTagStrip("a<p>b</p>", alloc) catch unreachable;
    try std.testing.expect(std.mem.eql(u8, stripped, "ab"));
    stripped = htmlTagStrip("a<p>b</p>c", alloc) catch unreachable;
    try std.testing.expect(std.mem.eql(u8, stripped, "abc"));
    stripped = htmlTagStrip("a<a img=\"\">b</a>c", alloc) catch unreachable;
    try std.testing.expect(std.mem.eql(u8, stripped, "abc"));
}

pub fn htmlEntityDecode(str: []const u8, allocator: Allocator) ![]const u8 {
    var newStr = try SimpleBuffer.SimpleU8.initSize(allocator, 0);
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
    const stripped = htmlEntityDecode("amp&amp;pam", alloc) catch unreachable;
    try std.testing.expect(std.mem.eql(u8, stripped, "amp&pam"));
}
