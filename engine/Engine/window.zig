const gpu = @import("gpu");
const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_X11", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

pub const Window = opaque {
    pub const Config = struct {
        size: ?struct { u32, u32 } = null,
        title: [:0]const u8,
        resizable: bool = true,
    };

    pub fn open(config: Config) !*Window {
        const monitor = c.glfwGetPrimaryMonitor() orelse return Error.get_monitor;
        const mode = c.glfwGetVideoMode(monitor) orelse return Error.get_video_mode;

        c.glfwWindowHint(c.GLFW_RESIZABLE, @intFromBool(config.resizable));
        c.glfwWindowHint(c.GLFW_REFRESH_RATE, mode.*.refreshRate);
        c.glfwWindowHint(c.GLFW_GREEN_BITS, mode.*.greenBits);
        c.glfwWindowHint(c.GLFW_BLUE_BITS, mode.*.blueBits);
        c.glfwWindowHint(c.GLFW_RED_BITS, mode.*.redBits);
        // c.glfwWindowHint(c.GLFW_DECORATED, @intFromBool(false));

        c.glfwWindowHint(c.GLFW_CLIENT_API, @intFromBool(false));

        const width: c_int = if (config.size == null) mode.*.width else @intCast(config.size.?[0]);
        const height: c_int = if (config.size == null) mode.*.height else @intCast(config.size.?[1]);

        const handle = c.glfwCreateWindow(width, height, config.title, null, null) orelse return Error.window_open_failed;

        _ = c.glfwSetFramebufferSizeCallback(handle, @ptrCast(&resizeCallback));
        _ = c.glfwSetMouseButtonCallback(handle, @ptrCast(&mousePressCallback));
        _ = c.glfwSetCursorPosCallback(handle, @ptrCast(&mouseMoveCallback));
        _ = c.glfwSetWindowCloseCallback(handle, @ptrCast(&closeCallback));
        _ = c.glfwSetWindowFocusCallback(handle, @ptrCast(&focusCallback));
        _ = c.glfwSetKeyCallback(handle, @ptrCast(&keyPressCallback));

        return @ptrCast(handle);
    }

    pub fn close(window: *Window) void {
        c.glfwDestroyWindow(@ptrCast(window));
    }

    pub fn surface(window: *Window, instance: *gpu.Instance) *gpu.Surface {
        const desc = gpu.SurfaceDescriptorFromXlibWindow{
            .chain = .{ .s_type = gpu.SType.surface_descriptor_from_xlib_window },
            .display = c.glfwGetX11Display().?,
            .window = c.glfwGetX11Window(@ptrCast(window)),
        };

        return instance.createSurface(&.{
            .next_in_chain = &desc.chain,
            .label = "XLib Surface",
        }).?;
    }

    pub fn size(window: *Window) struct { u32, u32 } {
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetWindowSize(@ptrCast(window), &width, &height);

        return .{ @intCast(width), @intCast(height) };
    }

    pub fn resize(window: *Window, dims: struct { u32, u32 }) void {
        c.glfwSetWindowSize(@ptrCast(window), @intCast(dims[0]), @intCast(dims[1]));
    }
};

fn resizeCallback(window: ?*Window, width: c_int, height: c_int) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .window_resize = .{
        .window = window,
        .width = @intCast(width),
        .height = @intCast(height),
    } });
}

fn closeCallback(window: ?*Window) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .window_close = window });
}

fn keyPressCallback(window: ?*Window, key: c_int, _: c_int, action: c_int, mods: c_int) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .key_press = .{
        .window = window,
        .key = @intCast(key),
        .action = @enumFromInt(action),
        .mods = @bitCast(@as(u8, @truncate(@as(u32, @intCast(mods))))),
    } });
}

fn mousePressCallback(window: ?*Window, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .mouse_press = .{
        .window = window,
        .button = @enumFromInt(button),
        .action = @enumFromInt(action),
        .mods = @bitCast(@as(u8, @truncate(@as(u32, @intCast(mods))))),
    } });
}

fn mouseMoveCallback(window: ?*Window, x: f64, y: f64) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .mouse_move = .{
        .window = window,
        .x = x,
        .y = y,
    } });
}

fn focusCallback(window: ?*Window, focused: c_int) callconv(.C) void {
    var engine = Engine._ctx orelse return;
    engine.addEvent(.{ .window_focus = .{
        .window = window,
        .focused = focused != 0,
    } });
}

pub const Error = error{
    get_monitor,
    get_video_mode,
    window_open_failed,
};

const Engine = @import("../Engine.zig");

const Modifiers = @import("event.zig").Modifiers;
