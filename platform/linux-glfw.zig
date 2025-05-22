const Engine = @import("Engine");
const Window = Engine.Window;
const Event = Engine.Event;

const gpu = @import("gpu");
const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_X11", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

export fn Engine_Init(_: *Engine) callconv(.C) void {
    if (c.glfwInit() == c.GLFW_FALSE) unreachable;
}

export fn Engine_Deinit(_: *Engine) callconv(.C) void {
    c.glfwTerminate();
}

var globalEngine: ?*Engine = null;

export fn Engine_Poll(engine: *Engine) callconv(.C) void {
    globalEngine = engine;
    c.glfwPollEvents();
    globalEngine = null;
}

export fn Engine_Time(_: *Engine) callconv(.C) f64 {
    return c.glfwGetTime();
}

export fn Engine_Window_Open(config: *const Window.Config) callconv(.C) ?*Window {
    const monitor = c.glfwGetPrimaryMonitor() orelse return null;
    const mode = c.glfwGetVideoMode(monitor) orelse return null;

    c.glfwWindowHint(c.GLFW_RESIZABLE, @intFromBool(config.resizable));
    c.glfwWindowHint(c.GLFW_REFRESH_RATE, mode.*.refreshRate);
    c.glfwWindowHint(c.GLFW_GREEN_BITS, mode.*.greenBits);
    c.glfwWindowHint(c.GLFW_BLUE_BITS, mode.*.blueBits);
    c.glfwWindowHint(c.GLFW_RED_BITS, mode.*.redBits);

    c.glfwWindowHint(c.GLFW_CLIENT_API, @intFromBool(false));

    const width: c_int = if (config.size == null) mode.*.width else @intCast(config.size.?[0]);
    const height: c_int = if (config.size == null) mode.*.height else @intCast(config.size.?[1]);

    const handle = c.glfwCreateWindow(width, height, config.title, null, null) orelse return null;

    _ = c.glfwSetFramebufferSizeCallback(handle, @ptrCast(&resizeCallback));
    _ = c.glfwSetMouseButtonCallback(handle, @ptrCast(&mousePressCallback));
    _ = c.glfwSetCursorPosCallback(handle, @ptrCast(&mouseMoveCallback));
    _ = c.glfwSetWindowCloseCallback(handle, @ptrCast(&closeCallback));
    _ = c.glfwSetWindowFocusCallback(handle, @ptrCast(&focusCallback));
    _ = c.glfwSetKeyCallback(handle, @ptrCast(&keyPressCallback));

    return @ptrCast(handle);
}

export fn Engine_Window_Close(window: *Window) callconv(.C) void {
    c.glfwDestroyWindow(@ptrCast(window));
}

export fn Engine_Window_Size(window: *Window) callconv(.C) extern struct { width: u32, height: u32 } {
    var width: c_int = undefined;
    var height: c_int = undefined;

    c.glfwGetWindowSize(@ptrCast(window), &width, &height);

    return .{ .width = @intCast(width), .height = @intCast(height) };
}

export fn Engine_Window_Surface(window: *Window, instance: *gpu.Instance) ?*gpu.Surface {
    const desc = gpu.SurfaceDescriptorFromXlibWindow{
        .chain = .{ .s_type = gpu.SType.surface_descriptor_from_xlib_window },
        .display = c.glfwGetX11Display() orelse return null,
        .window = c.glfwGetX11Window(@ptrCast(window)),
    };

    return instance.createSurface(&.{
        .next_in_chain = &desc.chain,
        .label = "XLib Surface",
    });
}

fn resizeCallback(window: ?*Window, width: c_int, height: c_int) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .window_resize = .{
        .window = window,
        .width = @intCast(width),
        .height = @intCast(height),
    } });
}

fn closeCallback(window: ?*Window) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .window_close = window });
}

fn keyPressCallback(window: ?*Window, key: c_int, _: c_int, action: c_int, mods: c_int) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .key_press = .{
        .window = window,
        .key = @intCast(key),
        .action = @enumFromInt(action),
        .mods = @bitCast(@as(u8, @truncate(@as(u32, @intCast(mods))))),
    } });
}

fn mousePressCallback(window: ?*Window, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .mouse_press = .{
        .window = window,
        .button = @enumFromInt(button),
        .action = @enumFromInt(action),
        .mods = @bitCast(@as(u8, @truncate(@as(u32, @intCast(mods))))),
    } });
}

fn mouseMoveCallback(window: ?*Window, x: f64, y: f64) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .mouse_move = .{
        .window = window,
        .x = x,
        .y = y,
    } });
}

fn focusCallback(window: ?*Window, focused: c_int) callconv(.C) void {
    var engine = globalEngine orelse return;
    engine.addEvent(.{ .window_focus = .{
        .window = window,
        .focused = focused != 0,
    } });
}
