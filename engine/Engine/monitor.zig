pub const Monitor = opaque {
    pub inline fn primary() ?*Monitor {
        return Engine_Monitor_Primary();
    }

    pub inline fn size(monitor: *Monitor) struct { u32, u32 } {
        const dims = Engine_Monitor_Size(monitor);
        return .{ dims.width, dims.height };
    }

    extern fn Engine_Monitor_Primary() callconv(.C) ?*Monitor;
    extern fn Engine_Monitor_Size(*Monitor) callconv(.C) extern struct { width: u32, height: u32 };
};
