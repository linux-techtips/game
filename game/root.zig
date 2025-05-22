const std = @import("std");
const gpu = @import("gpu");

const State = struct {
    window: *Window,
    surface: *gpu.Surface,
    adapter: *gpu.Adapter,
    device: *gpu.Device,
    queue: *gpu.Queue,
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    uniform_buffer: *gpu.Buffer,
    time: f64,

    depth_texture_view: ?*gpu.TextureView,
    pipeline: ?*gpu.RenderPipeline,
    bindgroup: ?*gpu.BindGroup,
};

const vertex_data = [_]f32{
    -0.5, -0.5, -0.3, 1.0, 1.0, 1.0,
    0.5,  -0.5, -0.3, 1.0, 1.0, 1.0,
    0.5,  0.5,  -0.3, 1.0, 1.0, 1.0,
    -0.5, 0.5,  -0.3, 1.0, 1.0, 1.0,

    0.0,  0.0,  0.5,  0.5, 0.5, 0.5,
};

const index_data = [_]u16{
    0, 1, 2,
    0, 2, 3,
    0, 1, 4,
    1, 2, 4,
    2, 3, 4,
    3, 0, 4,
};

const Uniform = extern struct {
    color: @Vector(4, f32),
    time: f32,
    ratio: f32,
};

export fn Plug_Startup(engine: *Engine) ?*State {
    var state = engine.allocator.create(State) catch return null;

    state.window = Window.open(.{ .title = "Game", .size = .{ 1200, 720 } }) catch unreachable;

    state.depth_texture_view = null;
    state.pipeline = null;
    state.bindgroup = null;

    const instance = gpu.Instance.create(&.{}).?;
    defer instance.release();

    state.surface = state.window.surface(instance);

    const adapter = blk: {
        const resp = instance.requestAdapterSync(&.{
            .power_preference = .high_performance,
            .backend_type = .vulkan,
            .compatible_surface = state.surface,
        });
        break :blk resp.adapter.?;
    };
    defer adapter.release();

    state.device = blk: {
        const resp = adapter.requestDeviceSync(&.{
            .required_limits = null,
        });
        break :blk resp.device.?;
    };

    state.queue = state.device.getQueue().?;

    state.vertex_buffer = state.device.createBuffer(&.{
        .label = "Vertex Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
        .size = @sizeOf(@TypeOf(vertex_data)),
    }).?;

    state.index_buffer = state.device.createBuffer(&.{
        .label = "Index Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.index,
        .size = @sizeOf(@TypeOf(index_data)),
    }).?;

    state.uniform_buffer = state.device.createBuffer(&.{
        .label = "Uniform Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.uniform,
        .size = @sizeOf(Uniform),
    }).?;

    loaded(engine, state);

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) void {
    state.pipeline.?.release();
    state.bindgroup.?.release();
    state.depth_texture_view.?.release();
    state.uniform_buffer.release();
    state.index_buffer.release();
    state.vertex_buffer.release();
    state.queue.release();
    state.device.release();
    state.surface.release();

    state.window.close();
    engine.allocator.destroy(state);
}

export fn Plug_Update(engine: *Engine, state: *State) bool {
    loop: for (engine.poll()) |event| switch (event) {
        .window_close => |window| if (window == state.window) return false,
        .window_resize => |e| {
            if (e.window != state.window) continue :loop;

            makeDepthTexture(state, .depth24_plus, .{ e.width, e.height });
            state.surface.configure(&.{
                .width = e.width,
                .height = e.height,
                .format = .bgra8_unorm_srgb,
                .present_mode = .fifo,
                .device = state.device,
            });
        },
        .reload => loaded(engine, state),
        else => continue :loop,
    };

    render(engine, state);

    return true;
}

fn render(engine: *Engine, state: *State) void {
    const surface_texture = blk: {
        var res: gpu.SurfaceTexture = undefined;
        state.surface.getCurrentTexture(&res);

        break :blk switch (res.status) {
            .success => res.texture,
            .timeout => @panic("ruh roh"),
            else => |status| std.debug.panic("{s}", .{@tagName(status)}),
        };
    };
    defer surface_texture.release();

    const surface_view = surface_texture.createView(&.{
        .format = surface_texture.getFormat(),
        .dimension = .@"2d",
    }).?;

    const encoder = state.device.createCommandEncoder(&.{}).?;

    const uniform = Uniform{
        .time = @floatCast(engine.time()),
        .ratio = blk: {
            const width, const height = state.window.size();
            break :blk @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        },
        .color = .{ 0.0, 1.0, 0.4, 1.0 },
    };

    state.queue.writeBuffer(state.vertex_buffer, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
    state.queue.writeBuffer(state.index_buffer, 0, &index_data, @sizeOf(@TypeOf(index_data)));
    state.queue.writeBuffer(state.uniform_buffer, 0, &uniform, @sizeOf(Uniform));

    const color_attachments = [_]gpu.ColorAttachment{
        gpu.ColorAttachment{
            .view = surface_view,
            .clear_value = .{},
        },
    };

    const depth_attachment = gpu.DepthStencilAttachment{
        .view = state.depth_texture_view.?,
        .depth_clear_value = 1.0,
        .depth_load_op = .clear,
        .depth_store_op = .store,
        .stencil_load_op = .clear,
        .stencil_store_op = .store,
        .stencil_read_only = @intFromBool(true),
    };

    const render_pass = encoder.beginRenderPass(&.{
        .color_attachment_count = color_attachments.len,
        .color_attachments = &color_attachments,
        .depth_stencil_attachment = &depth_attachment,
    }).?;

    render_pass.setPipeline(state.pipeline.?);
    render_pass.setVertexBuffer(0, state.vertex_buffer, 0, state.vertex_buffer.getSize());
    render_pass.setIndexBuffer(state.index_buffer, .uint16, 0, state.index_buffer.getSize());
    render_pass.setBindGroup(0, state.bindgroup.?, 0, null);

    render_pass.drawIndexed(index_data.len, 1, 0, 0, 0);

    render_pass.end();
    render_pass.release();

    const command = encoder.finish(&.{}).?;
    encoder.release();

    state.queue.submit(&.{command});
    command.release();

    state.surface.present();
    defer surface_view.release();

    _ = state.device.poll(false, null);
}

fn loaded(_: *Engine, state: *State) void {
    if (state.pipeline) |pipeline| pipeline.release();
    if (state.bindgroup) |bindgroup| bindgroup.release();
    if (state.depth_texture_view) |depth_texture_view| depth_texture_view.release();

    const shader_desc = gpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader = state.device.createShaderModule(&.{ .next_in_chain = &shader_desc.chain }).?;
    defer shader.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        gpu.VertexAttribute{
            .shader_location = 0,
            .format = .float32x3,
            .offset = 0,
        },
        gpu.VertexAttribute{
            .shader_location = 1,
            .format = .float32x3,
            .offset = 3 * @sizeOf(f32),
        },
    };

    const vertex_layouts = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout{
            .array_stride = 6 * @sizeOf(f32),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
    };

    const vertex_state = gpu.VertexState{
        .module = shader,
        .entry_point = "vert",
        .buffer_count = vertex_layouts.len,
        .buffers = &vertex_layouts,
    };

    const fragment_targets = [_]gpu.ColorTargetState{
        gpu.ColorTargetState{ .format = .bgra8_unorm_srgb, .blend = &gpu.BlendState{
            .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
            .alpha = .{ .operation = .add, .src_factor = .zero, .dst_factor = .one },
        } },
    };

    const fragment_state = gpu.FragmentState{
        .module = shader,
        .entry_point = "frag",
        .targets = &fragment_targets,
        .target_count = fragment_targets.len,
    };

    const bindgroup_layout_entries = [_]gpu.BindGroupLayoutEntry{gpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = gpu.ShaderStage.vertex | gpu.ShaderStage.fragment,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = @sizeOf(Uniform),
        },
    }};

    const bindgroup_layout = state.device.createBindGroupLayout(&.{
        .entry_count = bindgroup_layout_entries.len,
        .entries = &bindgroup_layout_entries,
    }).?;
    defer bindgroup_layout.release();

    const bindgroup_entries = [_]gpu.BindGroupEntry{
        gpu.BindGroupEntry{
            .binding = 0,
            .buffer = state.uniform_buffer,
            .size = @sizeOf(Uniform),
        },
    };

    state.bindgroup = state.device.createBindGroup(&.{
        .layout = bindgroup_layout,
        .entries = &bindgroup_entries,
        .entry_count = bindgroup_entries.len,
    }).?;

    const layout = state.device.createPipelineLayout(&.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &.{bindgroup_layout},
    }).?;
    defer layout.release();

    const depth_format = gpu.TextureFormat.depth24_plus;
    const depth_stencil_state = gpu.DepthStencilState{
        .depth_compare = .less,
        .depth_write_enabled = @intFromBool(true),
        .format = depth_format,
        .stencil_read_mask = 0,
        .stencil_write_mask = 0,
        .stencil_back = .{},
        .stencil_front = .{},
    };

    const size = state.window.size();
    makeDepthTexture(state, depth_format, size);
    state.surface.configure(&.{
        .width = size[0],
        .height = size[1],
        .format = .bgra8_unorm_srgb,
        .present_mode = .fifo,
        .device = state.device,
    });

    state.pipeline = state.device.createRenderPipeline(&.{
        .layout = layout,
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .depth_stencil = &depth_stencil_state,
        .primitive = .{},
        .multisample = .{},
    }).?;
}

fn makeDepthTexture(state: *State, format: gpu.TextureFormat, size: struct { u32, u32 }) void {
    const depth_texture = state.device.createTexture(&.{
        .format = format,
        .size = .{ .width = size[0], .height = size[1] },
        .usage = gpu.TextureUsage.render_attachment,
        .view_format_count = 1,
        .view_formats = @ptrCast(&format),
    }).?;
    defer depth_texture.release();

    state.depth_texture_view = depth_texture.createView(&.{
        .aspect = .depth_only,
        .array_layer_count = 1,
        .mip_level_count = 1,
        .dimension = .@"2d",
        .format = format,
    }).?;
}

const Engine = @import("Engine");
const Window = Engine.Window;
