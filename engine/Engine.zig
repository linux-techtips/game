const std = @import("std");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const Engine = @This();

allocator: std.mem.Allocator,

_frametime: f64 = 0,

_events: [256]Engine.Event = undefined,
_events_len: u8 = 0,

pub fn init(allocator: std.mem.Allocator) ?Engine {
    if (c.glfwInit() == c.GLFW_FALSE) return null;
    return .{ .allocator = allocator };
}

pub fn deinit(_: *Engine) void {
    c.glfwTerminate();
}

pub inline fn frametime(engine: *const Engine) f64 {
    return engine._frametime;
}

pub inline fn fps(engine: *const Engine) f64 {
    return 1 / engine._frametime;
}

pub var _ctx: ?*Engine = null;

pub inline fn addEvent(engine: *Engine, event: Engine.Event) void {
    engine._events[engine._events_len] = event;
    engine._events_len += 1;
}

pub fn poll(engine: *Engine) []Engine.Event {
    _ctx = engine;

    c.glfwPollEvents();

    const events = engine._events[0..engine._events_len];

    engine._events_len = 0;
    _ctx = null;

    return events;
}

pub fn time(_: *Engine) f64 {
    return c.glfwGetTime();
}

pub const Window = @import("Engine/window.zig").Window;
pub const Plugin = @import("Engine/plugin.zig").Plugin;
pub const Event = @import("Engine/event.zig").Event;

pub const log = std.log.scoped(.engine);
pub const gpu = @import("gpu");
