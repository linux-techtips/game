const std = @import("std");
const zlm = @import("zlm");
const gpu = @import("gpu");
const obj = @import("obj");

const renderer = @import("renderer.zig");
const Camera = @import("Camera.zig");

const State = struct {
    window: *Window,
    focused: bool,
    render_context: renderer.Context,

    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    uniform_buffer: *gpu.Buffer,
    time: f64,

    pipeline: ?*gpu.RenderPipeline,
    bindgroup: ?*gpu.BindGroup,

    camera: Camera,
    cam_proj: Camera.Projection,
    cam_uniform: ?Camera.Uniform,
};

const vertex_data = [_]f32{
    -0.5, -0.5, -0.3, 0.0,    -1.0,   0.0,  1.0, 0.0, 0.0,
    0.5,  -0.5, -0.3, 0.0,    -1.0,   0.0,  0.0, 1.0, 0.0,
    0.5,  0.5,  -0.3, 0.0,    -1.0,   0.0,  0.0, 0.0, 1.0,
    -0.5, 0.5,  -0.3, 0.0,    -1.0,   0.0,  0.5, 0.5, 0.5,

    -0.5, -0.5, -0.3, 0.0,    -0.848, 0.53, 1.0, 0.0, 0.0,
    0.5,  -0.5, -0.3, 0.0,    -0.848, 0.53, 0.0, 1.0, 0.0,
    0.0,  0.0,  0.5,  0.0,    -0.848, 0.53, 0.0, 0.0, 1.0,

    0.5,  -0.5, -0.3, 0.848,  0.0,    0.53, 1.0, 0.0, 0.0,
    0.5,  0.5,  -0.3, 0.848,  0.0,    0.53, 0.0, 1.0, 0.0,
    0.0,  0.0,  0.5,  0.848,  0.0,    0.53, 0.0, 0.0, 1.0,

    0.5,  0.5,  -0.3, 0.0,    0.848,  0.53, 1.0, 0.0, 0.0,
    -0.5, 0.5,  -0.3, 0.0,    0.848,  0.53, 0.0, 1.0, 0.0,
    0.0,  0.0,  0.5,  0.0,    0.848,  0.53, 0.0, 0.0, 1.0,

    -0.5, 0.5,  -0.3, -0.848, 0.0,    0.53, 1.0, 0.0, 0.0,
    -0.5, -0.5, -0.3, -0.848, 0.0,    0.53, 0.0, 1.0, 0.0,
    0.0,  0.0,  0.5,  -0.848, 0.0,    0.53, 0.0, 0.0, 1.0,
};

const index_data = [_]u16{
    0,  1,  2,
    0,  2,  3,
    4,  5,  6,
    7,  8,  9,
    10, 11, 12,
    13, 14, 15,
};

const Uniform = extern struct {
    model: zlm.Mat,
    time: f32,
    _pad: [3]f32 = undefined,
};

export fn Plug_Startup(engine: *Engine) ?*State {
    var state = engine.allocator.create(State) catch return null;

    state.window = Window.open(.{ .title = "Game", .size = .{ 1200, 720 } }) orelse unreachable;
    state.render_context = renderer.Context.init(state.window);
    state.focused = true;

    state.pipeline = null;
    state.bindgroup = null;

    state.camera = .{ .pos = @splat(0), .eul = .{} };
    state.cam_proj = Camera.Projection.init(1200, 720, 0.01, 100, 45);
    state.cam_uniform = null;

    loaded(engine, state);

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) void {
    state.cam_uniform.?.deinit();
    state.pipeline.?.release();
    state.bindgroup.?.release();
    state.uniform_buffer.release();
    state.index_buffer.release();
    state.vertex_buffer.release();

    state.render_context.deinit();
    state.window.close();
    engine.allocator.destroy(state);
}

export fn Plug_Update(engine: *Engine, state: *State) bool {
    loop: for (engine.poll()) |event| switch (event) {
        .window_close => |window| {
            if (window == state.window) return false;
        },
        .window_resize => |e| {
            if (e.window != state.window) continue :loop;

            state.render_context.reconfigure(e.width, e.height);
        },
        .mouse_press => |e| if (e.window == state.window) {
            if (!state.focused and e.action == .press) {
                state.window.captureCursor();
                state.focused = true;
            }
        },
        .key_press => |e| if (e.window == state.window) {
            if (e.key == .escape) {
                state.window.uncaptureCursor();
                state.focused = false;
            }
            if (e.action == .press or e.action == .repeat) state.camera.move(e.key, @floatCast(engine.frametime()));
            state.cam_uniform.?.update(state.render_context.queue, state.camera, state.cam_proj);
        },
        .mouse_move => |e| if (e.window == state.window) {
            state.camera.look(@floatCast(e.x), @floatCast(e.y), @floatCast(engine.frametime()));
            state.cam_uniform.?.update(state.render_context.queue, state.camera, state.cam_proj);
        },
        .reload => loaded(engine, state),
        else => continue :loop,
    };

    render(engine, state);

    return true;
}

fn render(engine: *Engine, state: *State) void {
    const frame = renderer.Frame.begin(&state.render_context);
    defer frame.end(&state.render_context);

    const time: f32 = @floatCast(engine.time());
    const model_trans = zlm.translation(0, 0, -10);
    const model_rotat = zlm.rotationZ(time);
    const model = zlm.mul(model_rotat, model_trans);

    const uniform = Uniform{
        .model = model,
        .time = time,
    };

    state.render_context.queue.writeBuffer(state.vertex_buffer, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
    state.render_context.queue.writeBuffer(state.index_buffer, 0, &index_data, @sizeOf(@TypeOf(index_data)));
    state.render_context.queue.writeBuffer(state.uniform_buffer, 0, &uniform, @sizeOf(Uniform));

    frame.render_pass.setPipeline(state.pipeline.?);
    frame.render_pass.setVertexBuffer(0, state.vertex_buffer, 0, state.vertex_buffer.getSize());
    frame.render_pass.setIndexBuffer(state.index_buffer, .uint16, 0, state.index_buffer.getSize());

    frame.render_pass.setBindGroup(0, state.cam_uniform.?.bindgroup, 0, null);
    frame.render_pass.setBindGroup(1, state.bindgroup.?, 0, null);

    frame.render_pass.drawIndexed(index_data.len, 1, 0, 0, 0);
}

fn loaded(_: *Engine, state: *State) void {
    if (state.cam_uniform) |cam_uniform| cam_uniform.deinit();
    if (state.pipeline) |pipeline| pipeline.release();
    if (state.bindgroup) |bindgroup| bindgroup.release();

    state.cam_uniform = Camera.Uniform.init(state.render_context.device);
    state.cam_uniform.?.update(state.render_context.queue, state.camera, state.cam_proj);

    state.vertex_buffer = state.render_context.device.createBuffer(&.{
        .label = "Vertex Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
        .size = @sizeOf(@TypeOf(vertex_data)),
    }).?;

    state.index_buffer = state.render_context.device.createBuffer(&.{
        .label = "Index Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.index,
        .size = @sizeOf(@TypeOf(index_data)),
    }).?;

    state.uniform_buffer = state.render_context.device.createBuffer(&.{
        .label = "Uniform Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.uniform,
        .size = @sizeOf(Uniform),
    }).?;

    const shader_desc = gpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader = state.render_context.device.createShaderModule(&.{ .next_in_chain = &shader_desc.chain }).?;
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
        gpu.VertexAttribute{
            .shader_location = 2,
            .format = .float32x3,
            .offset = 6 * @sizeOf(f32),
        },
    };

    const vertex_layouts = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout{
            .array_stride = 9 * @sizeOf(f32),
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

    const bindgroup_layout = state.render_context.device.createBindGroupLayout(&.{
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

    state.bindgroup = state.render_context.device.createBindGroup(&.{
        .layout = bindgroup_layout,
        .entries = &bindgroup_entries,
        .entry_count = bindgroup_entries.len,
    }).?;

    const layout = state.render_context.device.createPipelineLayout(&.{
        .bind_group_layout_count = 2,
        .bind_group_layouts = &.{ state.cam_uniform.?.layout, bindgroup_layout },
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

    state.pipeline = state.render_context.device.createRenderPipeline(&.{
        .layout = layout,
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .depth_stencil = &depth_stencil_state,
        .primitive = .{},
        .multisample = .{},
    }).?;
}

const Engine = @import("Engine");
const Window = Engine.Window;
