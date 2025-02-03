const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var loga = std.heap.loggingAllocator(std.heap.c_allocator);
const allocator = gpa.allocator();

pub fn main() !void {
    const body = "{\"a\": 1, \"b\":2}";
    const value = try do_parse(body);
    // const parsed_value = try std.json.parseFromSlice(std.json.Value, allocator, body, .{ .allocate = .alloc_always });
    // const value = &parsed_value.value;
    std.debug.print("main {*} {s}\n", .{ &value.value, @tagName(value.value) });
    const json = try std.json.stringifyAlloc(allocator, value.value, .{});
    std.debug.print("{s}\n", .{json});
}

fn do_parse(body: []const u8) !std.json.Parsed(std.json.Value) {
    std.debug.print("json parse {*} {} bytes\n", .{ body, body.len });
    const json_parse_result = std.json.parseFromSlice(std.json.Value, allocator, body, .{ .allocate = .alloc_always });
    if (json_parse_result) |json_parsed| {
        // const value = &json_parsed.value;
        // std.debug.print("parsed {*} {}\n", .{ value, value });
        return json_parsed;
    } else |err| {
        std.debug.print("parserr {any}\n", .{err});
        return err;
    }
}
