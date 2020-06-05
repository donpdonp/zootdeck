const std = @import("std");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

pub const States = enum {
    Init,
    Setup,
    Running,
};

pub var state: States = undefined;

pub fn init(allocator: *Allocator) !void {
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
    warn("STATE: {}\n", .{@tagName(state)});
}
