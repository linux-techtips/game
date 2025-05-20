const std = @import("std");

const GlobalAllocator = @This();

pub var arena: std.heap.ArenaAllocator = undefined;
var allocator: ?std.mem.Allocator = null;

pub fn get() *std.mem.Allocator {
    return &(allocator.?);
}

pub fn init() !void {
    @branchHint(.unlikely);
    if (allocator == null) {
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        allocator = arena.allocator();
    }
}

pub fn deinit() void {
    arena.deinit();
}

const Payload = usize;
const Align = @alignOf(Payload) * 2;
const Ptr = [*]align(Align) u8;

fn malloc(size: usize) callconv(.C) ?Ptr {
    GlobalAllocator.init() catch @panic("Failed to initialize global allocator");

    var mem = GlobalAllocator.get().alignedAlloc(u8, Align, size + Align) catch return null;
    @as(*Payload, @ptrCast(mem)).* = mem.len;

    // std.debug.print("malloc({}) => {*} - {}\n", .{ size, mem.ptr, mem.len });

    return mem[Align..].ptr;
}

fn calloc(bytes: usize, count: usize) callconv(.C) ?Ptr {
    const size = std.math.mul(usize, bytes, count) catch return null;
    const mem = malloc(size) orelse return null;

    @memset(mem[0..size], 0);
    return mem;
}

fn realloc(data: ?Ptr, new_size: usize) callconv(.C) ?Ptr {
    if (data == null) return malloc(new_size);

    GlobalAllocator.init() catch @panic("Failed to initialize global allocator");

    const old_ptr: Ptr = @ptrFromInt(@intFromPtr(data) - Align);
    const old_len = @as(*Payload, @ptrCast(old_ptr)).*;

    var new_mem = GlobalAllocator.get().realloc(old_ptr[0..old_len], new_size + Align) catch return null;
    @as(*Payload, @ptrCast(new_mem)).* = new_mem.len;

    // std.debug.print("realloc({*}, {}) => {*} - {}\n", .{ old_ptr, new_size, new_mem.ptr, new_mem.len });

    return new_mem[Align..].ptr;
}

fn free(data: ?Ptr) callconv(.C) void {
    if (data == null) return;

    GlobalAllocator.init() catch @panic("Failed to initialize global allocator");

    const ptr: Ptr = @ptrFromInt(@intFromPtr(data) - Align);
    const len = @as(*Payload, @ptrCast(ptr)).*;

    // std.debug.print("free({*}, {})\n", .{ ptr, len });

    return GlobalAllocator.get().free(ptr[0..len]);
}

comptime {
    const root = @import("root");
    if (@hasDecl(root, "override_libc_alloc") and root.override_libc_alloc) {
        @export(&malloc, .{ .name = "malloc" });
        @export(&calloc, .{ .name = "calloc" });
        @export(&realloc, .{ .name = "realloc" });
        @export(&free, .{ .name = "free" });
    }
}
