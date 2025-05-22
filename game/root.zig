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

    pipeline: ?*gpu.RenderPipeline,
    bindgroup: ?*gpu.BindGroup,
};

const vertex_data = [_]f32{
    -0.5, -0.5, -0.3, 1.0, 0.0, 0.0,
    0.5,  -0.5, -0.3, 0.0, 1.0, 0.0,
    0.5,  0.5,  -0.3, 0.0, 0.0, 1.0,
    -0.5, 0.5,  -0.3, 1.0, 0.0, 0.0,

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

export fn Plug_Startup(engine: *Engine) ?*State {
    var state = engine.allocator.create(State) catch return null;

    state.window = Window.open(.{ .title = "Game", .size = .{ 1200, 720 } }) catch unreachable;

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

    const size = state.window.size();
    state.surface.configure(&.{
        .width = size[0],
        .height = size[1],
        .format = .bgra8_unorm_srgb,
        .present_mode = .fifo,
        .device = state.device,
    });

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
        .size = 256 + (8 * @sizeOf(f32)),
    }).?;

    loaded(engine, state);

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) void {
    state.pipeline.?.release();
    state.bindgroup.?.release();
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

    const surface_texture = blk: {
        var res: gpu.SurfaceTexture = undefined;
        state.surface.getCurrentTexture(&res);

        break :blk switch (res.status) {
            .success => res.texture,
            .timeout => return true,
            else => |status| std.debug.panic("{s}", .{@tagName(status)}),
        };
    };
    defer surface_texture.release();

    const surface_view = surface_texture.createView(&.{
        .format = surface_texture.getFormat(),
        .dimension = .@"2d",
    }).?;

    const encoder = state.device.createCommandEncoder(&.{}).?;

    const time: f32 = @floatCast(engine.time());
    const width, const height = state.window.size();
    const ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    state.queue.writeBuffer(state.vertex_buffer, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
    state.queue.writeBuffer(state.index_buffer, 0, &index_data, @sizeOf(@TypeOf(index_data)));
    state.queue.writeBuffer(state.uniform_buffer, 0, &time, @sizeOf(f32));
    state.queue.writeBuffer(state.uniform_buffer, 256, &ratio, @sizeOf(f32));

    const render_pass = encoder.beginRenderPass(&.{
        .color_attachment_count = 1,
        .color_attachments = &.{.{
            .view = surface_view,
            // .clear_value = .{ .r = 1.0, .g = 0.2, .b = 0.2 },
            .clear_value = .{},
        }},
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
    return true;
}

fn loaded(_: *Engine, state: *State) void {
    if (state.pipeline) |pipeline| pipeline.release();
    if (state.bindgroup) |bindgroup| bindgroup.release();

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

    const bindgroup_layout_entries = [_]gpu.BindGroupLayoutEntry{ gpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = gpu.ShaderStage.vertex,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = 4 * @sizeOf(f32),
        },
    }, gpu.BindGroupLayoutEntry{
        .binding = 1,
        .visibility = gpu.ShaderStage.vertex,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = 4 * @sizeOf(f32),
        },
    } };

    const bindgroup_layout = state.device.createBindGroupLayout(&.{
        .entry_count = bindgroup_layout_entries.len,
        .entries = &bindgroup_layout_entries,
    }).?;
    defer bindgroup_layout.release();

    const bindgroup_entries = [_]gpu.BindGroupEntry{
        gpu.BindGroupEntry{
            .binding = 0,
            .buffer = state.uniform_buffer,
            .size = 4 * @sizeOf(u32),
        },
        gpu.BindGroupEntry{
            .binding = 1,
            .buffer = state.uniform_buffer,
            .offset = 256,
            .size = 4 * @sizeOf(f32),
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

    state.pipeline = state.device.createRenderPipeline(&.{
        .layout = layout,
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .primitive = .{},
        .multisample = .{},
    }).?;
}

const Engine = @import("Engine");
const Window = Engine.Window;
