const std = @import("std");
const warn = std.debug.warn;
const thread = @import("./thread.zig");
const Allocator = std.mem.Allocator;
var allocator: *Allocator = undefined;

const c = @cImport({
    @cInclude("unistd.h");
});

pub fn init(myAllocator: *Allocator) !void {
    allocator = myAllocator;
}

pub fn go(data: ?*c_void) callconv(.C) ?*c_void {
    var data8 = @alignCast(@alignOf(thread.Actor), data);
    var actor = @ptrCast(*thread.Actor, data8);
    warn("heartbeat thread start {*} \n", .{actor});
    while (true) {
        _ = c.usleep(3 * 1000000);
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
