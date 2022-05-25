const std = @import("std");
const util = @import("./util.zig");
const warn = util.log;
const Allocator = std.mem.Allocator;
var allocator: Allocator = undefined;

pub const States = enum {
    Init,
    Setup,
    Running,
};

pub var state: States = undefined;

pub fn init(my_allocator: Allocator) !void {
    _ = my_allocator;
    setState(States.Init);
    if (state != States.Init) return error.StatemachineSetupFail;
}

pub fn needNetRefresh() bool {
    if (state == States.Setup) {
        setState(States.Running);
        return true;
    } else {
        return false;
    }
}

pub fn setState(new_state: States) void {
    state = new_state;
    warn("STATE: {s}\n", .{@tagName(state)});
}
