pub const Engine = @import("Engine.zig");
const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var engine = Engine.init(arena.allocator());
    defer engine.deinit();

    var plugin, var game = try Engine.Plugin.load("./zig-out/lib/libgame.so");
    defer plugin.unload();

    var state = game.startup(&engine, null) orelse {
        Engine.log.err("failed to initialize plugin state: '{s}'", .{plugin.path});
        std.process.exit(1);
    };
    defer game.shutdown(&engine, state);

    var old_stat = try std.fs.cwd().statFile(plugin.path);
    var old_time = engine.time();

    loop: while (true) {
        const new_time = engine.time();
        defer old_time = new_time;

        engine._frametime = new_time - old_time;

        if (!game.update(&engine, state)) break :loop;
        const new_stat = try std.fs.cwd().statFile(plugin.path);
        if (new_stat.mtime > old_stat.mtime) {
            game = try plugin.reload();
            old_stat = new_stat;

            state = game.startup(&engine, state) orelse {
                Engine.log.err("failed to reload plugin state: '{s}'", .{plugin.path});
                std.process.exit(1);
            };
        }
    }
}
