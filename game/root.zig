const WindowSystem = @import("WindowSystem.zig");
const Camera = @import("Camera.zig");
const Engine = @import("Engine");

const gfx = @import("gfx.zig");
const gpu = @import("gpu");
const std = @import("std");

const State = struct {
    window_system: WindowSystem,
    monitor: *Engine.Monitor,
    window: *Engine.Window,
    ctx: gfx.Context,
};

export fn Startup(engine: *Engine, old: ?*State) ?*State {
    if (old != null) return old;

    const state = engine.allocator.create(State) catch unreachable;

    state.monitor = Engine.Monitor.primary() orelse unreachable;
    state.ctx = gfx.Context.init() catch unreachable;

    const mWidth, const mHeight = state.monitor.size();

    state.window_system = WindowSystem.init(engine.allocator) catch unreachable;
    _ = state.window_system.openWindow(&state.ctx, mWidth, mHeight, "Game", .{ .pos = .{ 0, 0 } }) catch unreachable;
    _ = state.window_system.openWindow(&state.ctx, 640, 480, "Game", .{ .pos = .{ 300, 400 } }) catch unreachable;

    const handle = state.window_system.openWindow(&state.ctx, 640, 480, "Game", .{}) catch unreachable;
    state.window = state.window_system.pool.getColumnAssumeLive(handle, .window);

    return state;
}

export fn Shutdown(engine: *Engine, state: *State) void {
    state.window_system.deinit();
    state.ctx.deinit();

    engine.allocator.destroy(state);
}

export fn Update(engine: *Engine, state: *State) bool {
    for (engine.poll()) |event| {
        if (!state.window_system.update(&state.ctx, &event)) return false;
    }

    const mWidth, const mHeight = state.monitor.size();
    const wWidth, const wHeight = state.window.size();

    const center_x: f32 = @floatFromInt((mWidth / 2) - (wWidth / 2));
    const center_y: f32 = @floatFromInt((mHeight / 2) - (wHeight / 2));

    const radius = @min(center_x, center_y);
    const angle = engine.time() * 2.5;

    state.window.setPos(
        @intFromFloat(center_x + radius * @cos(angle)),
        @intFromFloat(center_y + radius * @sin(angle)),
    );

    const camera_texture = state.ctx.device.createTexture(&gpu.TextureDescriptor{
        .label = "Camera Texture",
        .format = .bgra8_unorm_srgb,
        .size = .{ .width = mWidth, .height = mHeight, .depth_or_array_layers = 1 },
        .usage = gpu.TextureUsage.copy_dst | gpu.TextureUsage.copy_src | gpu.TextureUsage.render_attachment,
    }).?;
    defer {
        camera_texture.destroy();
        camera_texture.release();
    }

    const vertex_data = [_]f32{
        0.0,  0.5,  1, 0, 0,
        -0.5, -0.5, 0, 1, 0,
        0.5,  -0.5, 0, 0, 1,
    };

    const vertex_buffer = state.ctx.device.createBuffer(&.{
        .label = "Vertex Data",
        .size = @sizeOf(@TypeOf(vertex_data)),
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
    }).?;
    defer vertex_buffer.release();

    state.ctx.queue.writeBuffer(vertex_buffer, 0, &vertex_data, vertex_buffer.getSize());

    {
        const view = camera_texture.createView(&.{}).?;
        defer view.release();

        const frame = gfx.Frame.begin(&state.ctx, view);

        const pipeline = gfx.createBasicPipeline(&state.ctx);
        defer pipeline.release();

        frame.pass.setPipeline(pipeline);
        frame.pass.setVertexBuffer(0, vertex_buffer, 0, vertex_buffer.getSize());
        frame.pass.draw(3, 1, 0, 0);

        frame.pass.end();
        frame.pass.release();

        var textures = std.ArrayList(*gpu.Texture).initCapacity(engine.allocator, 32) catch unreachable;
        defer textures.deinit();

        var it = state.window_system.pool.liveHandles();
        while (it.next()) |handle| {
            textures.appendAssumeCapacity(state.window_system.getSurfaceTexture(handle));
            const texture = textures.getLast();

            const window = state.window_system.pool.getColumnAssumeLive(handle, .window);
            const x, const y = window.getPos();

            const dst_x: u32, const dst_y: u32 = .{ if (x < 0) @intCast(-x) else 0, if (y < 0) @intCast(-y) else 0 };
            const src_x: u32, const src_y: u32 = .{ @intCast(@max(0, x)), @intCast(@max(0, y)) };

            const copy_w, const copy_h = .{ @min(texture.getWidth() - dst_x, camera_texture.getWidth() - src_x), @min(texture.getHeight() - dst_y, camera_texture.getHeight() - src_y) };

            frame.encoder.copyTextureToTexture(
                &gpu.ImageCopyTexture{
                    .origin = .{ .x = src_x, .y = src_y },
                    .texture = camera_texture,
                },
                &gpu.ImageCopyTexture{
                    .origin = .{ .x = dst_x, .y = dst_y },
                    .texture = texture,
                },
                &.{ .width = copy_w, .height = copy_h, .depth_or_array_layers = 1 },
            );
        }

        const commands = frame.encoder.finish(&.{}).?;
        state.ctx.queue.submit(&.{commands});
        commands.release();

        _ = state.ctx.device.poll(false, null);

        it = state.window_system.pool.liveHandles();
        while (it.next()) |handle| {
            const surface = state.window_system.pool.getColumnAssumeLive(handle, .surface);
            surface.present();
        }

        for (textures.items) |texture| {
            texture.release();
        }
    }

    return true;
}
