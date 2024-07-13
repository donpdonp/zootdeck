const std = @import("std");
const warn = std.debug.print;
const Allocator = std.mem.Allocator;

const AnyErrorOutStream = std.io.OutStream(anyerror);

const enabled = false;

/// Formerly LoggingAllocator
/// This allocator is used in front of another allocator and logs to the provided stream
/// on every call to the allocator. Stream errors are ignored.
/// If https://github.com/ziglang/zig/issues/2586 is implemented, this API can be improved.
pub const WarningAllocator = struct {
    allocator: Allocator,
    parent_allocator: *Allocator,
    total: u64,

    const Self = @This();

    pub fn init(parent_allocator: *Allocator) Self {
        return Self{
            .allocator = Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .parent_allocator = parent_allocator,
            .total = 0,
        };
    }

    fn realloc(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        if (enabled) {
            if (old_mem.len == 0) {
                warn("allocation of {!} ", new_size);
            } else {
                warn("resize from {} to {!} ", old_mem.len, new_size);
            }
        }
        const result = self.parent_allocator.reallocFn(self.parent_allocator, old_mem, old_align, new_size, new_align);
        if (enabled) {
            if (result) |buff| {
                //self.total = mem_size_diff; zig bug
                warn("success!\n");
            } else |err| {
                warn("failure!\n");
            }
        }
        return result;
    }

    fn shrink(allocator: *Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        const self = @fieldParentPtr(Self, "allocator", allocator);
        const mem_size_diff = old_mem.len - new_size;
        //self.total -= mem_size_diff;
        const result = self.parent_allocator.shrinkFn(self.parent_allocator, old_mem, old_align, new_size, new_align);
        if (new_size == 0) {
            warn("free of {} bytes success! total {!}\n", old_mem.len, mem_size_diff);
        } else {
            warn("shrink from {} bytes to {} bytes success! total {!}\n", old_mem.len, new_size, mem_size_diff);
        }
        return result;
    }
};
