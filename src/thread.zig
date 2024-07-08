// thread.zig
const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;
var allocator: Allocator = undefined;
const ipc = @import("./ipc/epoll.zig");
const config = @import("./config.zig");

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("pthread.h");
    @cInclude("sys/epoll.h");
});

pub const Actor = struct { thread_id: c.pthread_t, client: *ipc.Client, payload: *CommandVerb, recvback: *const fn (*Command) void, name: []const u8 };

pub const Command = packed struct { id: u16, verb: *const CommandVerb, actor: *Actor };

pub const CommandVerb = packed union { login: *config.LoginInfo, http: *config.HttpInfo, column: *config.ColumnInfo, auth: *config.ColumnAuth, idle: u16 };

pub const ActorList = std.AutoArrayHashMap(u64, *Actor);
var actors: ActorList = undefined;

pub fn init(myAllocator: Allocator) !void {
    allocator = myAllocator;
    actors = ActorList.init(allocator);
    try ipc.init();
}

pub fn register_main_tid(mtid: u64) !void {
    var actor = try allocator.create(Actor);
    actor.name = "main";
    try actors.put(mtid, actor);
}

pub fn name(tid: u64) []const u8 {
    return if (actors.get(tid)) |actor| actor.name else "-unregistered-thread-";
}

pub fn create(
    actor_name: []const u8,
    startFn: *const fn (?*anyopaque) callconv(.C) ?*anyopaque,
    startParams: *CommandVerb,
    recvback: *const fn (*Command) void,
) !*Actor {
    var actor = try allocator.create(Actor);
    actor.client = ipc.newClient(allocator);
    actor.payload = startParams; //unused
    ipc.dial(actor.client, "");
    actor.recvback = recvback;
    actor.name = actor_name;
    //ipc.register(actor.client, recvback);
    const null_pattr = @as([*c]const c.union_pthread_attr_t, @ptrFromInt(0));
    const pt_err = c.pthread_create(&actor.thread_id, null_pattr, startFn, actor);
    try actors.putNoClobber(actor.thread_id, actor);
    if (pt_err == 0) {
        return actor;
    } else {
        warn("ERROR thread pthread_create err: {} {}\n", .{ pt_err, actor });
    }
    return error.BadValue;
}

pub fn signal(actor: *Actor, command: *Command) void {
    command.actor = actor; // fill in the command
    //const command_address_bytes: *const [8]u8 = @ptrCast([*]const u8, command)[0..8]; // not OK
    const command_address_bytes: *align(8) const [8]u8 = std.mem.asBytes(&command); // OK
    //const command_address_bytes = std.mem.asBytes(&@as(usize, @ptrToInt(command))); // OK
    warn("tid {} is signaling command {*} id {} {*} to thread.wait() \n", .{ actor.thread_id, command, command.id, command.verb });
    ipc.send(actor.client, command_address_bytes);
}

pub fn destroy(actor: *Actor) void {
    ipc.close(actor.client);
    _ = actors.swapRemove(actor.thread_id);
    allocator.destroy(actor);
}

pub fn self() c.pthread_t {
    return c.pthread_self();
}

pub fn wait() void {
    const client = ipc.wait();

    var bufArray = [_]u8{0} ** 16; // arbitrary receive buffer
    const buf: []u8 = ipc.read(client, bufArray[0..]);
    if (buf.len == 0) {
        // todo: skip read() and pass ptr with event_data
        warn("thread.wait ipc.read no socket payload! DEFLECTED!\n", .{});
    } else {
        const b8: *[@sizeOf(usize)]u8 = @as(*[@sizeOf(usize)]u8, @ptrCast(buf.ptr));
        const command: *Command = std.mem.bytesAsValue(*Command, b8).*;
        var iter = actors.iterator();
        while (iter.next()) |entry| {
            const actor = entry.value_ptr.*;
            if (actor.client == client) {
                actor.recvback(command);
                break;
            }
        }
    }
}

pub fn join(jthread: c.pthread_t, joinret: *?*anyopaque) c_int {
    //pub extern fn pthread_join(__th: pthread_t, __thread_return: ?[*](?*c_void)) c_int;
    return c.pthread_join(jthread, @as(?[*]?*anyopaque, @ptrCast(joinret))); //expected type '?[*]?*c_void' / void **value_ptr
}
