const std = @import("std");

// TODO: GET THIS WORKING!!!
pub const override_libc_alloc = false;

const GlobalAllocator = @import("GlobalAllocator.zig");
const Engine = @import("Engine.zig");
const Plugin = @import("Plugin.zig");

pub fn main() !void {
    log.debug("initializing", .{});
    defer log.debug("shutting down", .{});

    try GlobalAllocator.init();
    defer GlobalAllocator.deinit();

    const allocator = GlobalAllocator.get().*;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    const lib: [:0]const u8 = "./zig-out/lib/libgame.so";

    var game = try Plugin.load(lib);
    defer game.unload();

    const state = game.vtable.startup(&engine) orelse @panic("Failed to initialize game.");
    defer game.vtable.shutdown(&engine, state);
    game.vtable.loaded(&engine, state);

    var old_stat = try std.fs.cwd().statFile(lib);
    while (game.vtable.update(&engine, state)) {
        const new_stat = try std.fs.cwd().statFile(lib);
        if (new_stat.mtime > old_stat.mtime) {
            try game.reload();
            game.vtable.loaded(&engine, state);
            old_stat = new_stat;
        }

        engine.poll();
    }
}

pub const log = std.log.scoped(.engine);
