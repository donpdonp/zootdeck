// main.zig
const std = @import("std");
const builtin = @import("builtin");

const warn = std.debug.print;

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("orx.h");
});

pub fn main() void {
    c.orx_Execute();
}
