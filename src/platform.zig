const GlobalAllocator = @import("GlobalAllocator.zig");
const Engine = @import("Engine.zig");
const wgpu = @import("wgpu");
const std = @import("std");

const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_X11", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

export fn Engine_Init(_: *Engine) void {
    if (c.glfwInit() == c.GLFW_FALSE) unreachable;
}

export fn Engine_Deinit(_: *Engine) void {
    c.glfwTerminate();
}

export fn Engine_Poll(engine: *Engine) void {
    c.glfwPollEvents();
    engine._time = Engine_Time(engine);
}

export fn Engine_Time(_: *Engine) f64 {
    return c.glfwGetTime();
}

export fn Engine_Delta(engine: *Engine) f64 {
    const now = c.glfwGetTime();
    const off = now - engine._time;

    return off;
}

export fn Engine_FPS(engine: *Engine) f64 {
    const delta = Engine_Delta(engine);
    return if (delta > 0) 1.0 / delta else 0.0;
}

export fn Engine_Window_Open(_: *Engine, window: *Window, config: *const Window.Config) void {
    c.glfwWindowHint(c.GLFW_RESIZABLE, @intCast(@intFromBool(config.resizable)));
    c.glfwWindowHint(c.GLFW_CLIENT_API, @intCast(@intFromBool(false)));

    window.handle = @ptrCast(c.glfwCreateWindow(@intCast(config.width), @intCast(config.height), @ptrCast(config.title), null, null) orelse unreachable);
}

export fn Engine_Window_Close(_: *Engine, window: *Window) void {
    c.glfwDestroyWindow(@ptrCast(window.handle));
}

export fn Engine_Window_SetTitle(window: *Window, title: [*:0]const u8) void {
    c.glfwSetWindowTitle(@ptrCast(window.handle), title);
}

export fn Engine_Window_ShouldClose(window: *Window) bool {
    return c.glfwWindowShouldClose(@ptrCast(window.handle)) == c.GLFW_TRUE;
}

export fn Engine_Window_Surface(window: *Window, instance: *wgpu.Instance) *wgpu.Surface {
    const desc = wgpu.SurfaceDescriptorFromXlibWindow{
        .chain = .{ .s_type = wgpu.SType.surface_descriptor_from_xlib_window },
        .display = c.glfwGetX11Display().?,
        .window = c.glfwGetX11Window(@ptrCast(window.handle)),
    };

    return instance.createSurface(&.{
        .next_in_chain = &desc.chain,
        .label = "XLib Surface",
    }).?;
}

export fn Engine_Window_On_Resize(window: *Window, callback: *const fn (handle: ?Window.Handle, width: c_int, height: c_int) callconv(.C) void) callconv(.C) void {
    _ = c.glfwSetWindowSizeCallback(@ptrCast(window.handle), @ptrCast(callback));
}

export fn Engine_Window_Get_Size(window: *Window) callconv(.C) extern struct { width: u32, height: u32 } {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetWindowSize(@ptrCast(window.handle), &width, &height);

    return .{ .width = @intCast(width), .height = @intCast(height) };
}

const Window = Engine.Window;
