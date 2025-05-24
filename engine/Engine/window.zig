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

    pub inline fn isFocused(window: *Window) bool {
        return Engine_Window_Isfocused(window);
    }

    pub inline fn focus(window: *Window) void {
        Engine_Window_Focus(window);
    }

    pub inline fn unfocus(window: *Window) void {
        Engine_Window_Unfocus(window);
    }

    pub inline fn captureCursor(window: *Window) void {
        Engine_Window_Capture_Cursor(window);
    }

    pub inline fn uncaptureCursor(window: *Window) void {
        Engine_Window_Uncapture_Cursor(window);
    }

    extern fn Engine_Window_Open(*const Config) callconv(.C) ?*Window;
    extern fn Engine_Window_Close(*Window) callconv(.C) void;
    extern fn Engine_Window_Size(*Window) callconv(.C) extern struct { width: u32, height: u32 };
    extern fn Engine_Window_Surface(*Window, *gpu.Instance) callconv(.C) ?*gpu.Surface;
    extern fn Engine_Window_Focus(*Window) callconv(.C) void;
    extern fn Engine_Window_Unfocus(*Window) callconv(.C) void;
    extern fn Engine_Window_Isfocused(*Window) callconv(.C) bool;
    extern fn Engine_Window_Capture_Cursor(*Window) callconv(.C) void;
    extern fn Engine_Window_Uncapture_Cursor(*Window) callconv(.C) void;
};
