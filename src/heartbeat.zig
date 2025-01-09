const std = @import("std");
const util = @import("./util.zig");
const warn = std.debug.print;
const thread = @import("./thread.zig");
const Allocator = std.mem.Allocator;
var allocator: Allocator = undefined;

const c = @cImport({
    @cInclude("unistd.h");
});

pub fn init(myAllocator: Allocator) !void {
    allocator = myAllocator;
}

pub fn go(actor_ptr: ?*anyopaque) callconv(.C) ?*anyopaque {
    const actor = @as(*thread.Actor, @ptrCast(@alignCast(actor_ptr)));
    util.log("heartbeat init()", .{});
    const sleep_seconds = 60;
    while (true) {
        _ = c.usleep(sleep_seconds * 1000000);
        // signal crazy
        var command = allocator.create(thread.Command) catch unreachable;
        var verb = allocator.create(thread.CommandVerb) catch unreachable;
        verb.idle = 0;
        command.id = 3;
        command.verb = verb;
        thread.signal(actor, command);
    }
    return null;
}
