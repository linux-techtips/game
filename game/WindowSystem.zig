const gfx = @import("gfx.zig");
const std = @import("std");
const gpu = @import("gpu");

pub const Pool = Engine.Pool(8, 8, *Window, struct {
    window: *Window,
    surface: *gpu.Surface,
});

pub const Handle = Pool.Handle;

const System = @This();

pool: Pool,

pub fn init(allocator: std.mem.Allocator) Error!System {
    return .{
        .pool = try Pool.initMaxCapacity(allocator),
    };
}

pub fn deinit(system: *System) void {
    var it = system.pool.liveHandles();
    while (it.next()) |handle| system.closeWindow(handle);

    system.pool.deinit();
}

pub fn openWindow(system: *System, ctx: *const gfx.Context, width: u32, height: u32, title: [:0]const u8, config: Window.Config) Error!Handle {
    const window = Window.open(width, height, title, config) orelse return Error.OpenWindow;
    const surface = window.surface(ctx.instance) orelse return error.WindowSurface;

    surface.configure(&.{
        .width = width,
        .height = height,
        .format = .bgra8_unorm_srgb,
        .present_mode = .mailbox,
        .device = ctx.device,
        .usage = gpu.TextureUsage.copy_dst | gpu.TextureUsage.copy_src | gpu.TextureUsage.render_attachment,
    });

    const handle = try system.pool.add(.{ .window = window, .surface = surface });

    window.setUserPointer(@ptrFromInt(handle.id));

    return handle;
}

pub fn windowToHandle(_: *const System, window: *Window) Handle {
    return .{ .id = @intCast(@intFromPtr(window.getUserPointer())) };
}

pub fn closeWindow(system: *System, handle: Handle) void {
    const columns = system.pool.getColumnsAssumeLive(handle);
    columns.surface.release();
    columns.window.close();

    system.pool.removeAssumeLive(handle);
}

pub fn getSurfaceTexture(system: *const System, handle: Handle) *gpu.Texture {
    const surface = system.pool.getColumnAssumeLive(handle, .surface);

    var res: gpu.SurfaceTexture = undefined;
    surface.getCurrentTexture(&res);

    return switch (res.status) {
        .success => res.texture,
        else => @panic("ruh roh"),
    };
}

pub fn update(system: *System, ctx: *const gfx.Context, event: *const Engine.Event) bool {
    switch (event.*) {
        .window_close => |window| {
            const handle = system.windowToHandle(window orelse return true);
            system.closeWindow(handle);

            if (system.pool.liveHandleCount() == 0) return false;
        },
        .window_resize => |e| {
            const handle = system.windowToHandle(e.window orelse return true);
            const surface = system.pool.getColumnAssumeLive(handle, .surface);

            surface.configure(&.{
                .width = e.width,
                .height = e.height,
                .format = .bgra8_unorm_srgb,
                .present_mode = .mailbox,
                .device = ctx.device,
                .usage = gpu.TextureUsage.copy_dst | gpu.TextureUsage.copy_src | gpu.TextureUsage.render_attachment,
            });
        },
        else => {},
    }

    return true;
}

pub const Error = std.mem.Allocator.Error || Pool.Error || error{
    OpenWindow,
    WindowSurface,
};

const Engine = @import("Engine");
const Window = Engine.Window;
