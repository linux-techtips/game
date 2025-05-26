const Engine = @import("Engine");
const gpu = @import("gpu");
const std = @import("std");

const Renderer = @This();

surface: *gpu.Surface,
device: *gpu.Device,
queue: *gpu.Queue,

depth_texture: *gpu.Texture,
depth_view: *gpu.TextureView,

pub fn init(window: *Engine.Window) Renderer {
    const instance = gpu.Instance.create(&.{}).?;
    defer instance.release();

    const surface = window.surface(instance).?;

    const adapter = blk: {
        const resp = instance.requestAdapterSync(&.{
            .power_preference = .high_performance,
            .backend_type = .vulkan,
            .compatible_surface = surface,
        });

        break :blk resp.adapter.?;
    };
    defer adapter.release();

    const device = blk: {
        const resp = adapter.requestDeviceSync(&.{
            .required_limits = null,
        });

        break :blk resp.device.?;
    };

    const queue = device.getQueue().?;

    const width, const height = window.size();

    configureSurface(device, surface, width, height);

    const depth_texture, const depth_view = createDepthTextureAndView(device, width, height);

    return .{
        .surface = surface,
        .device = device,
        .queue = queue,
        .depth_texture = depth_texture,
        .depth_view = depth_view,
    };
}

pub fn deinit(renderer: *const Renderer) void {
    renderer.depth_texture.destroy();
    renderer.depth_view.release();
    renderer.queue.release();
    renderer.device.release();
    renderer.surface.release();
}

pub fn reconfigure(renderer: *Renderer, width: u32, height: u32) void {
    renderer.depth_view.release();

    renderer.depth_texture.destroy();
    renderer.depth_texture.release();

    renderer.depth_texture, renderer.depth_view = createDepthTextureAndView(renderer.device, width, height);

    configureSurface(renderer.device, renderer.surface, width, height);
}

pub fn beginFrame(renderer: *Renderer) Frame {
    return Frame.begin(renderer);
}

fn createDepthTextureAndView(device: *gpu.Device, width: u32, height: u32) struct { *gpu.Texture, *gpu.TextureView } {
    const format = gpu.TextureFormat.depth24_plus;
    const texture = device.createTexture(&.{
        .format = format,
        .size = .{ .width = width, .height = height },
        .usage = gpu.TextureUsage.render_attachment,
        .view_format_count = 1,
        .view_formats = &.{format},
    }).?;

    const view = texture.createView(&.{
        .aspect = .depth_only,
        .array_layer_count = 1,
        .mip_level_count = 1,
        .dimension = .@"2d",
        .format = format,
    }).?;

    return .{ texture, view };
}

fn configureSurface(device: *gpu.Device, surface: *gpu.Surface, width: u32, height: u32) void {
    surface.configure(&.{
        .width = width,
        .height = height,
        .format = .bgra8_unorm_srgb,
        .present_mode = .fifo,
        .device = device,
    });
}

pub const Frame = struct {
    surface_texture: *gpu.Texture,
    surface_view: *gpu.TextureView,
    encoder: *gpu.CommandEncoder,
    render_pass: *gpu.RenderPassEncoder,

    pub fn begin(renderer: *Renderer) Frame {
        const surface_texture = blk: {
            var res: gpu.SurfaceTexture = undefined;
            renderer.surface.getCurrentTexture(&res);

            break :blk switch (res.status) {
                .success => res.texture,
                else => |status| std.debug.panic("{s}", .{@tagName(status)}),
            };
        };

        const surface_view = surface_texture.createView(&.{
            .format = surface_texture.getFormat(),
            .dimension = .@"2d",
        }).?;

        const encoder = renderer.device.createCommandEncoder(&.{}).?;

        const color_attachment = gpu.ColorAttachment{
            .view = surface_view,
            .clear_value = .{},
        };

        const depth_attachment = gpu.DepthStencilAttachment{
            .view = renderer.depth_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .stencil_load_op = .clear,
            .stencil_store_op = .store,
            .stencil_read_only = @intFromBool(true),
        };

        const render_pass = encoder.beginRenderPass(&.{
            .color_attachment_count = 1,
            .color_attachments = &.{color_attachment},
            .depth_stencil_attachment = &depth_attachment,
        }).?;

        return .{
            .surface_texture = surface_texture,
            .surface_view = surface_view,
            .encoder = encoder,
            .render_pass = render_pass,
        };
    }

    pub fn end(frame: *const Frame, renderer: *Renderer) void {
        frame.render_pass.end();
        frame.render_pass.release();

        const command = frame.encoder.finish(&.{}).?;
        frame.encoder.release();

        renderer.queue.submit(&.{command});
        command.release();

        renderer.surface.present();

        _ = renderer.device.poll(false, null);

        frame.surface_view.release();
        frame.surface_texture.release();
    }
};
