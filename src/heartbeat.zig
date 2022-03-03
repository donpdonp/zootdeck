const std = @import("std");
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
    var data8 = @alignCast(@alignOf(thread.Actor), actor_ptr);
    var actor = @ptrCast(*thread.Actor, data8);
    const seconds = 60;
    warn("heartbeat mainloop thread.self()={} actor.thread_id={} \n", .{ thread.self(), actor.thread_id });
    while (true) {
        _ = c.usleep(seconds * 1000000);
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
