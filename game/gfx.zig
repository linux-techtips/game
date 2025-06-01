const gpu = @import("gpu");

pub const Context = struct {
    instance: *gpu.Instance,
    device: *gpu.Device,
    queue: *gpu.Queue,

    pub fn init() Error!Context {
        const instance = gpu.Instance.create(&.{}) orelse return Error.instance_create;

        const adapter = blk: {
            const resp = instance.requestAdapterSync(&.{});

            break :blk resp.adapter orelse {
                Engine.log.err("request adapter failed - {s} {?s}\n", .{ @tagName(resp.status), resp.message });
                return Error.adapter_request;
            };
        };
        defer adapter.release();

        const device = blk: {
            const resp = adapter.requestDeviceSync(&.{
                .required_limits = null,
            });

            break :blk resp.device orelse {
                Engine.log.err("request device failed - {s} {?s}\n", .{ @tagName(resp.status), resp.message });
                return Error.device_request;
            };
        };

        const queue = device.getQueue() orelse return Error.queue_create;

        return .{
            .instance = instance,
            .device = device,
            .queue = queue,
        };
    }

    pub fn deinit(ctx: *const Context) void {
        ctx.queue.release();
        ctx.device.release();
        ctx.instance.release();
    }
};

pub fn createBasicPipeline(ctx: *const Context) *gpu.RenderPipeline {
    const shader_desc = gpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader_module = ctx.device.createShaderModule(&.{
        .next_in_chain = &shader_desc.chain,
    }).?;
    defer shader_module.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        gpu.VertexAttribute{
            .format = .float32x2,
            .offset = 0,
            .shader_location = 0,
        },
        gpu.VertexAttribute{
            .format = .float32x3,
            .offset = 2 * @sizeOf(f32),
            .shader_location = 1,
        },
    };

    const vertex_layout = gpu.VertexBufferLayout{
        .array_stride = 5 * @sizeOf(f32),
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
        .step_mode = .vertex,
    };

    const vertex_state = gpu.VertexState{ .module = shader_module, .entry_point = "vert", .buffer_count = 1, .buffers = &.{vertex_layout} };

    const fragment_targets = [_]gpu.ColorTargetState{
        gpu.ColorTargetState{ .format = .bgra8_unorm_srgb, .blend = &gpu.BlendState{
            .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
            .alpha = .{ .operation = .add, .src_factor = .zero, .dst_factor = .one },
        } },
    };

    const fragment_state = gpu.FragmentState{
        .module = shader_module,
        .entry_point = "frag",
        .target_count = fragment_targets.len,
        .targets = &fragment_targets,
    };

    return ctx.device.createRenderPipeline(&.{
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .primitive = .{},
        .multisample = .{},
    }).?;
}

pub const Frame = struct {
    encoder: *gpu.CommandEncoder,
    pass: *gpu.RenderPassEncoder,

    pub fn begin(ctx: *const Context, view: *gpu.TextureView) Frame {
        const encoder = ctx.device.createCommandEncoder(&.{}).?;

        const color_attachment = gpu.ColorAttachment{
            .view = view,
            .clear_value = .{},
        };

        const pass = encoder.beginRenderPass(&.{
            .color_attachment_count = 1,
            .color_attachments = &.{color_attachment},
        }).?;

        return .{
            .encoder = encoder,
            .pass = pass,
        };
    }

    pub fn end(frame: *const Frame, ctx: *const Context) void {
        frame.pass.end();
        frame.pass.release();

        const commands = frame.encoder.finish(&.{}).?;
        frame.encoder.release();

        ctx.queue.submit(&.{commands});
        commands.release();

        _ = ctx.device.poll(false, null);
    }
};

pub const Error = error{
    instance_create,
    adapter_request,
    device_request,
    queue_create,
};

const Engine = @import("Engine");
