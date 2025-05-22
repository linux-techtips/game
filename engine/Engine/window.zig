const gpu = @import("gpu");

pub const Window = opaque {
    pub const Config = struct {
        size: ?struct { u32, u32 } = null,
        title: [:0]const u8,
        resizable: bool = true,
    };

    pub inline fn open(config: Config) ?*Window {
        return Engine_Window_Open(&config);
    }

    pub inline fn close(window: *Window) void {
        Engine_Window_Close(window);
    }

    pub inline fn size(window: *Window) struct { u32, u32 } {
        const dims = Engine_Window_Size(window);
        return .{ dims.width, dims.height };
    }

    pub inline fn surface(window: *Window, instance: *gpu.Instance) ?*gpu.Surface {
        return Engine_Window_Surface(window, instance);
    }

    extern fn Engine_Window_Open(*const Config) callconv(.C) ?*Window;
    extern fn Engine_Window_Close(*Window) callconv(.C) void;
    extern fn Engine_Window_Size(*Window) callconv(.C) extern struct { width: u32, height: u32 };
    extern fn Engine_Window_Surface(*Window, *gpu.Instance) callconv(.C) ?*gpu.Surface;
};
