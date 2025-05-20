const Engine = @import("Engine.zig");
const wgpu = @import("wgpu");
const std = @import("std");

const State = struct {
    window: *Engine.Window,
    surface: *wgpu.Surface,
    adapter: *wgpu.Adapter,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    vertex_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    uniform_buffer: *wgpu.Buffer,
    time: f64,

    pipeline: ?*wgpu.RenderPipeline,
    bindgroup: ?*wgpu.BindGroup,
};

const vertex_data = [_]f32{
    // x,   y,     r,   g,   b
    -0.5, -0.5, 1.0, 0.0, 0.0,
    0.5,  -0.5, 0.0, 1.0, 0.0,
    0.5,  0.5,  0.0, 0.0, 1.0,
    -0.5, 0.5,  1.0, 1.0, 0.0,
};

const index_data = [_]u16{
    0, 1, 2,
    0, 2, 3,
};

export fn Plug_Startup(engine: *Engine) callconv(.C) ?*State {
    var state = engine.allocator.create(State) catch return null;

    state.window = engine.openWindow(.{ .width = 1200, .height = 720 }) catch return null;
    state.time = engine.time();

    state.pipeline = null;
    state.bindgroup = null;

    const instance = wgpu.Instance.create(&.{}).?;
    defer instance.release();

    state.surface = @ptrCast(state.window.surface(@ptrCast(instance)));

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

    state.surface.configure(&.{
        .width = 1200,
        .height = 720,
        .format = .bgra8_unorm_srgb,
        .present_mode = .fifo,
        .device = state.device,
    });

    state.vertex_buffer = state.device.createBuffer(&.{
        .label = "Vertex Data",
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.vertex,
        .size = @sizeOf(@TypeOf(vertex_data)),
    }).?;

    state.index_buffer = state.device.createBuffer(&.{
        .label = "Index Data",
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.index,
        .size = @sizeOf(@TypeOf(index_data)),
    }).?;

    state.uniform_buffer = state.device.createBuffer(&.{
        .label = "Uniform Data",
        .usage = wgpu.BufferUsage.copy_dst | wgpu.BufferUsage.uniform,
        .size = 256 + (8 * @sizeOf(f32)),
    }).?;

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) callconv(.C) void {
    state.pipeline.?.release();
    state.bindgroup.?.release();
    state.uniform_buffer.release();
    state.index_buffer.release();
    state.vertex_buffer.release();
    state.queue.release();
    state.device.release();
    state.surface.release();

    engine.closeWindow(state.window);
    engine.allocator.destroy(state);
}

export fn Plug_Loaded(_: *Engine, state: *State) callconv(.C) void {
    if (state.pipeline) |pipeline| pipeline.release();
    if (state.bindgroup) |bindgroup| bindgroup.release();

    global_state = state;

    state.window.onResize(&onResize);

    const shader_desc = wgpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader = state.device.createShaderModule(&.{ .next_in_chain = &shader_desc.chain }).?;
    defer shader.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        wgpu.VertexAttribute{
            .shader_location = 0,
            .format = .float32x2,
            .offset = 0,
        },
        wgpu.VertexAttribute{
            .shader_location = 1,
            .format = .float32x3,
            .offset = 2 * @sizeOf(f32),
        },
    };

    const vertex_layouts = [_]wgpu.VertexBufferLayout{
        wgpu.VertexBufferLayout{
            .array_stride = 5 * @sizeOf(f32),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
    };

    const vertex_state = wgpu.VertexState{
        .module = shader,
        .entry_point = "vert",
        .buffer_count = vertex_layouts.len,
        .buffers = &vertex_layouts,
    };

    const fragment_targets = [_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{ .format = .bgra8_unorm_srgb, .blend = &wgpu.BlendState{
            .color = .{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one_minus_src_alpha },
            .alpha = .{ .operation = .add, .src_factor = .zero, .dst_factor = .one },
        } },
    };

    const fragment_state = wgpu.FragmentState{
        .module = shader,
        .entry_point = "frag",
        .targets = &fragment_targets,
        .target_count = fragment_targets.len,
    };

    const bindgroup_layout_entries = [_]wgpu.BindGroupLayoutEntry{ wgpu.BindGroupLayoutEntry{
        .binding = 0,
        .visibility = wgpu.ShaderStage.vertex,
        .buffer = .{
            .type = .uniform,
            .min_binding_size = 4 * @sizeOf(f32),
        },
    }, wgpu.BindGroupLayoutEntry{
        .binding = 1,
        .visibility = wgpu.ShaderStage.vertex,
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

    const bindgroup_entries = [_]wgpu.BindGroupEntry{
        wgpu.BindGroupEntry{
            .binding = 0,
            .buffer = state.uniform_buffer,
            .size = 4 * @sizeOf(u32),
        },
        wgpu.BindGroupEntry{
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

export fn Plug_Update(engine: *Engine, state: *State) callconv(.C) bool {
    const surface_texture = blk: {
        var res: wgpu.SurfaceTexture = undefined;
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
    const dims = state.window.getSize();
    const ratio = @as(f32, @floatFromInt(dims.width)) / @as(f32, @floatFromInt(dims.height));

    state.queue.writeBuffer(state.vertex_buffer, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
    state.queue.writeBuffer(state.index_buffer, 0, &index_data, @sizeOf(@TypeOf(index_data)));
    state.queue.writeBuffer(state.uniform_buffer, 0, &time, @sizeOf(f32));
    state.queue.writeBuffer(state.uniform_buffer, 256, &ratio, @sizeOf(f32));

    const render_pass = encoder.beginRenderPass(&.{
        .color_attachment_count = 1,
        .color_attachments = &.{.{
            .view = surface_view,
            //.clear_value = .{ .r = 1.0, .g = 0.2, .b = 0.2 },
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

    return !state.window.shouldClose();
}

var global_state: *State = undefined;

fn onResize(_: ?Engine.Window.Handle, width: c_int, height: c_int) callconv(.C) void {
    global_state.surface.configure(&.{
        .width = @intCast(width),
        .height = @intCast(height),
        .format = .bgra8_unorm_srgb,
        .present_mode = .fifo,
        .device = global_state.device,
    });
}
