const renderer = @import("renderer.zig");
const std = @import("std");
const gpu = @import("gpu");

const Engine = @import("Engine");

const Game = @This();

ctx: *renderer.Context,

pipeline: *gpu.RenderPipeline,
vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,

pub fn init(ctx: *renderer.Context) !*Game {
    return .{ .ctx = ctx };
}

pub fn deinit(game: *Game) void {
    game.ctx.deinit();
}
