pub const Event = union(enum) {
    window_resize: struct { window: ?*Window, width: u32, height: u32 },
    window_close: ?*Window,
    window_focus: struct {
        window: ?*Window,
        focused: bool,
    },
    key_press: struct {
        window: ?*Window,
        key: u16,
        action: Action,
        mods: Modifiers,
    },
    mouse_press: struct {
        window: ?*Window,
        button: enum(u8) {
            left = 0,
            right = 1,
            middle = 2,
            _,
        },
        action: Action,
        mods: Modifiers,
    },
    mouse_move: struct {
        window: ?*Window,
        x: f64,
        y: f64,
    },
    reload: void,
};

pub const Action = enum(u8) { release = 0, press = 1, repeat = 2 };
pub const Modifiers = packed struct(u8) {
    shift: u1 = 0,
    ctrl: u1 = 0,
    alt: u1 = 0,
    super: u1 = 0,
    caps: u1 = 0,
    num: u1 = 0,
    _pad: u2 = 0,
};

const Window = @import("window.zig").Window;
