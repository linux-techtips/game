const WindowSystem = @import("WindowSystem.zig");
const Camera = @import("Camera.zig");
const Engine = @import("Engine");

const gfx = @import("gfx.zig");
const gpu = @import("gpu");
const std = @import("std");

const State = struct { window_system: WindowSystem, ctx: gfx.Context };

export fn Startup(engine: *Engine, _: ?*State) ?*State {
    const state = engine.allocator.create(State) catch unreachable;

    state.ctx = gfx.Context.init() catch return null;

    state.window_system = WindowSystem.init(engine.allocator) catch unreachable;
    _ = state.window_system.openWindow(&state.ctx, 640, 480, "Game", .{}) catch unreachable;
    _ = state.window_system.openWindow(&state.ctx, 640, 480, "Game", .{}) catch unreachable;
    _ = state.window_system.openWindow(&state.ctx, 640, 480, "Game", .{}) catch unreachable;

    const camera_texture = state.ctx.device.createTexture(&gpu.TextureDescriptor{
        .label = "Camera Texture",
        .format = .bgra8_unorm_srgb,
        .size = .{ .width = 640, .height = 480, .depth_or_array_layers = 1 },
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

            frame.encoder.copyTextureToTexture(
                &gpu.ImageCopyTexture{
                    .origin = .{},
                    .texture = camera_texture,
                },
                &gpu.ImageCopyTexture{
                    .origin = .{},
                    .texture = texture,
                },
                &.{ .width = camera_texture.getWidth(), .height = camera_texture.getHeight(), .depth_or_array_layers = camera_texture.getDepthOrArrayLayers() },
            );
        }

        const commands = frame.encoder.finish(&.{}).?;
        state.ctx.queue.submit(&.{commands});
        commands.release();

        it = state.window_system.pool.liveHandles();
        while (it.next()) |handle| {
            const surface = state.window_system.pool.getColumnAssumeLive(handle, .surface);
            surface.present();
        }

        for (textures.items) |texture| {
            texture.release();
        }

        _ = state.ctx.device.poll(false, null);
    }

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

    return true;
}
