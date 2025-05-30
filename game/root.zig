const CardSystem = @import("CardSystem.zig");
const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");

const zlm = @import("zlm");
const std = @import("std");

const State = struct {
    card_system: CardSystem,
    renderer: Renderer,
    window: *Window,
    camera: struct {
        camera: Camera,
        projection: Camera.Projection,
        uniform: Camera.Uniform,
    },
};

export fn Plug_Startup(engine: *Engine, old: ?*State) ?*State {
    var state: *State = if (old != null) old.? else blk: {
        var new = engine.allocator.create(State) catch return null;

        new.window = Window.open(.{ .title = "Game", .size = .{ 640, 480 } }) orelse return null;
        new.card_system = CardSystem.init(engine) catch return null;
        new.renderer = Renderer.init(new.window);

        new.camera.camera = Camera{ .pos = .{ 0, 0, -1 } };
        new.camera.projection = Camera.Projection{ .aspect = @floatCast(new.window.aspect()) };
        new.camera.uniform = Camera.Uniform.init(new.renderer.device);
        new.camera.uniform.update(new.renderer.queue, zlm.mul(new.camera.camera.matrix(), new.camera.projection.perspective()));

        break :blk new;
    };

    state.card_system.loaded();

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) void {
    state.card_system.deinit();
    state.renderer.deinit();
    state.window.close();

    engine.allocator.destroy(state);
}

export fn Plug_Update(engine: *Engine, state: *State) bool {
    for (engine.poll()) |event| {
        switch (event) {
            .window_close => |window| return (window != state.window),
            .window_resize => |e| if (e.window == state.window) {
                state.renderer.reconfigure(e.width, e.height);
                state.camera.projection.aspect = @floatCast(state.window.aspect());
                state.camera.uniform.update(state.renderer.queue, zlm.mul(state.camera.camera.matrix(), state.camera.projection.perspective()));
            },
            else => {},
        }

        state.card_system.evented(&event);
    }

    state.card_system.render(&state.renderer, state.camera.uniform);
    state.card_system.update(engine);

    return true;
}

const Engine = @import("Engine");
const Window = Engine.Window;
