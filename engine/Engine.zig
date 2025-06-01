const std = @import("std");

const Engine = @This();

allocator: std.mem.Allocator,

_frametime: f64 = 0,

_events: [256]Engine.Event = undefined,
_events_len: u8 = 0,

pub inline fn init(allocator: std.mem.Allocator) Engine {
    var engine = Engine{ .allocator = allocator };
    Engine_Init(&engine);

    return engine;
}

pub inline fn deinit(engine: *Engine) void {
    Engine_Deinit(engine);
}

pub inline fn poll(engine: *Engine) []Engine.Event {
    Engine_Poll(engine);

    const events = engine._events[0..engine._events_len];
    engine._events_len = 0;

    return events;
}

pub inline fn time(engine: *Engine) f64 {
    return Engine_Time(engine);
}

pub inline fn frametime(engine: *const Engine) f64 {
    return engine._frametime;
}

pub inline fn fps(engine: *const Engine) f64 {
    return 1 / engine._frametime;
}

pub inline fn addEvent(engine: *Engine, event: Engine.Event) void {
    engine._events[engine._events_len] = event;
    engine._events_len += 1;
}

extern fn Engine_Init(*Engine) callconv(.C) void;
extern fn Engine_Deinit(*Engine) callconv(.C) void;
extern fn Engine_Poll(*Engine) callconv(.C) void;
extern fn Engine_Time(*Engine) callconv(.C) f64;

pub const Monitor = @import("Engine/monitor.zig").Monitor;
pub const Window = @import("Engine/window.zig").Window;
pub const Plugin = @import("Engine/Plugin.zig");
pub const Event = @import("Engine/event.zig").Event;
pub const Pool = @import("zpool").Pool;

pub const log = std.log.scoped(.engine);
