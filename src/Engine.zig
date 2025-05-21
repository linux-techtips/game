const std = @import("std");
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const Engine = @This();

allocator: std.mem.Allocator,
_time: f64 = 0,

pub inline fn init(allocator: std.mem.Allocator) Engine {
    var engine = Engine{ .allocator = allocator };
    Engine_Init(&engine);

    return engine;
}

pub inline fn deinit(engine: *Engine) void {
    Engine_Deinit(engine);
}

pub inline fn poll(engine: *Engine) void {
    Engine_Poll(engine);
}

pub inline fn time(engine: *Engine) f64 {
    return Engine_Time(engine);
}

pub inline fn delta(engine: *Engine) f64 {
    return Engine_Delta(engine);
}

pub inline fn fps(engine: *Engine) f64 {
    return Engine_FPS(engine);
}

pub inline fn openWindow(engine: *Engine, config: Window.Config) !*Window {
    const window = try engine.allocator.create(Window);
    Engine_Window_Open(engine, window, &config);

    return window;
}

pub inline fn closeWindow(engine: *Engine, window: *Window) void {
    Engine_Window_Close(engine, window);
    engine.allocator.destroy(window);
}

pub const Event = union(enum) {
    resize: struct { width: u32, height: u32 },
};

pub const Window = struct {
    pub const Handle = *anyopaque;
    pub const Config = struct {
        width: u32,
        height: u32,
        resizable: bool = true,
        title: [:0]const u8 = "",
    };

    pub const ResizeCallback = *const fn (ctx: ?*anyopaque, window: ?Window.Handle, width: u32, height: u32) callconv(.C) void;

    handle: Handle,

    pub inline fn shouldClose(window: *Window) bool {
        return Engine_Window_ShouldClose(window);
    }

    pub inline fn setTitle(window: *Window, title: [:0]const u8) void {
        return Engine_Window_SetTitle(window, title);
    }

    pub inline fn surface(window: *Window, ctx: *anyopaque) ?*anyopaque {
        return Engine_Window_Surface(window, ctx);
    }

    pub inline fn onResize(window: *Window, ctx: ?*anyopaque, callback: ResizeCallback) void {
        Engine_Window_On_Resize(window, ctx, callback);
    }

    pub inline fn getSize(window: *Window) struct { width: u32, height: u32 } {
        const dim = Engine_Window_Get_Size(window);
        return .{ .width = dim.width, .height = dim.height };
    }
};

extern fn Engine_Init(*Engine) void;
extern fn Engine_Deinit(*Engine) void;
extern fn Engine_Poll(*Engine) void;
extern fn Engine_Time(*Engine) f64;
extern fn Engine_Delta(*Engine) f64;
extern fn Engine_FPS(*Engine) f64;
extern fn Engine_Allocator(*Engine) *std.mem.Allocator;

extern fn Engine_Window_Open(*Engine, *Window, *const Window.Config) void;
extern fn Engine_Window_Close(*Engine, *Window) void;
extern fn Engine_Window_ShouldClose(*Window) bool;
extern fn Engine_Window_SetTitle(*Window, [*:0]const u8) void;
extern fn Engine_Window_Surface(*Window, *anyopaque) ?*anyopaque;
extern fn Engine_Window_On_Resize(*Window, ?*anyopaque, Window.ResizeCallback) void;
extern fn Engine_Window_Get_Size(*Window) extern struct { width: u32, height: u32 };
