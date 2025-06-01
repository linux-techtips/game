const Camera = @import("Camera.zig");
const Engine = @import("Engine");

const gfx = @import("gfx.zig");
const gpu = @import("gpu");

const State = struct {
    windows: [2]*Engine.Window,
};

export fn Startup(engine: *Engine, _: ?*State) ?*State {
    const state = engine.allocator.create(State) catch return null;
    state.windows = .{
        Engine.Window.open(640, 480, "Game1", .{ .resizable = false }).?,
        Engine.Window.open(640, 480, "Game2", .{ .resizable = false }).?,
    };

    const ctx = gfx.Context.init() catch return null;

    const camera_texture = ctx.device.createTexture(&gpu.TextureDescriptor{
        .label = "Camera Texture",
        .format = .bgra8_unorm_srgb,
        .size = .{ .width = 640, .height = 480, .depth_or_array_layers = 1 },
        .usage = gpu.TextureUsage.copy_dst | gpu.TextureUsage.copy_src | gpu.TextureUsage.render_attachment,
    }).?;
    defer {
        camera_texture.destroy();
        camera_texture.release();
    }

    const surfaces = blk: {
        var s: [2]*gpu.Surface = undefined;
        for (state.windows, 0..) |window, i| {
            s[i] = window.surface(ctx.instance).?;
            s[i].configure(&.{
                .width = 640,
                .height = 480,
                .format = .bgra8_unorm_srgb,
                .present_mode = .fifo,
                .device = ctx.device,
                .usage = gpu.TextureUsage.copy_dst | gpu.TextureUsage.copy_src | gpu.TextureUsage.render_attachment,
            });
        }

        break :blk s;
    };
    defer for (surfaces) |surface| surface.release();

    const surface_textures = blk: {
        var t: [2]*gpu.Texture = undefined;
        for (surfaces, 0..) |surface, i| {
            var res: gpu.SurfaceTexture = undefined;
            surface.getCurrentTexture(&res);

            t[i] = switch (res.status) {
                .success => res.texture,
                else => |status| @panic(@tagName(status)),
            };
        }

        break :blk t;
    };
    defer for (surface_textures) |texture| texture.release();

    const vertex_data = [_]f32{
        0.0,  0.5,  1, 0, 0,
        -0.5, -0.5, 0, 1, 0,
        0.5,  -0.5, 0, 0, 1,
    };

    const vertex_buffer = ctx.device.createBuffer(&.{
        .label = "Vertex Data",
        .size = @sizeOf(@TypeOf(vertex_data)),
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
    }).?;
    defer vertex_buffer.release();

    ctx.queue.writeBuffer(vertex_buffer, 0, &vertex_data, vertex_buffer.getSize());

    {
        const view = camera_texture.createView(&.{}).?;
        defer view.release();
        // const view = surface_texture.createView(&.{}).?;
        // defer view.release();

        const frame = gfx.Frame.begin(&ctx, view);

        const pipeline = gfx.createBasicPipeline(&ctx);
        defer pipeline.release();

        frame.pass.setPipeline(pipeline);
        frame.pass.setVertexBuffer(0, vertex_buffer, 0, vertex_buffer.getSize());
        frame.pass.draw(3, 1, 0, 0);

        frame.pass.end();

        for (surface_textures) |texture| {
            frame.encoder.copyTextureToTexture(
                &gpu.ImageCopyTexture{
                    .origin = .{},
                    .texture = camera_texture,
                },
                &gpu.ImageCopyTexture{
                    .origin = .{},
                    .texture = texture,
                },
                &.{ .width = texture.getWidth(), .height = texture.getHeight(), .depth_or_array_layers = texture.getDepthOrArrayLayers() },
            );
        }

        frame.pass.release();

        const commands = frame.encoder.finish(&.{}).?;
        ctx.queue.submit(&.{commands});
        commands.release();

        _ = ctx.device.poll(true, null);
    }

    for (surfaces) |surface| surface.present();

    return state;
}

export fn Shutdown(engine: *Engine, state: *State) void {
    for (state.windows) |window| window.close();
    engine.allocator.destroy(state);
}

export fn Update(engine: *Engine, _: *State) bool {
    for (engine.poll()) |event| switch (event) {
        .window_close => return false,
        else => continue,
    };

    return true;
}
