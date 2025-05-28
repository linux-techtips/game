const std = @import("std");
const zlm = @import("zlm");
const gpu = @import("gpu");
const obj = @import("obj");

const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");

// zig fmt: off
const vertex_data = [_]@Vector(2, f32) {
    .{ 0.0, 0.0 },
    .{ 0.5, 0.6 },
    .{ -0.7, 0.3 },
};

const State = struct {
    window: *Window,
    renderer: Renderer,

    pipeline: ?*gpu.RenderPipeline,
    vertex_buffer: ?*gpu.Buffer,
    uniform: ?Uniform,
};

export fn Plug_Startup(engine: *Engine) ?*State {
    var state = engine.allocator.create(State) catch return null;

    state.window = Window.open(.{ .title = "Game", .size = .{ 640, 480 } }) orelse unreachable;
    state.renderer = Renderer.init(state.window);

    state.vertex_buffer = null;
    state.pipeline = null;
    state.uniform = null;

    loaded(engine, state);

    return state;
}

export fn Plug_Shutdown(engine: *Engine, state: *State) void {
    state.uniform.?.deinit();
    state.pipeline.?.release();
    state.vertex_buffer.?.release();

    state.renderer.deinit();
    state.window.close();
    engine.allocator.destroy(state);
}

export fn Plug_Update(engine: *Engine, state: *State) bool {
    loop: for (engine.poll()) |event| switch (event) {
        .window_close => |window| if (window == state.window) {
            return false;
        },
        .window_resize => |e| if (e.window == state.window) {
            state.renderer.reconfigure(e.width, e.height);

            state.uniform = Uniform.init(state.renderer.device);
            const size: [2]f32 = blk: {
                const width, const height = state.window.size();
                break :blk .{ @floatFromInt(width), @floatFromInt(height) };
            };

            std.debug.print("{d:.2}\n", .{ size });

            state.renderer.queue.writeBuffer(state.uniform.?.buffer, 0, &size, @sizeOf(@TypeOf(size)));
        },
        .reload => loaded(engine, state),
        else => continue :loop,
    };

    render(engine, state);

    return true;
}

fn render(_: *Engine, state: *State) void {
    const frame = Renderer.beginFrame(&state.renderer);
    defer frame.end(&state.renderer);

    frame.render_pass.setPipeline(state.pipeline.?);
    frame.render_pass.setVertexBuffer(0, state.vertex_buffer.?, 0, state.vertex_buffer.?.getSize());
    frame.render_pass.setBindGroup(0, state.uniform.?.group, 0, null);

    frame.render_pass.draw(6, vertex_data.len, 0, 0);
}

fn loaded(_: *Engine, state: *State) void {
    if (state.vertex_buffer) |vertex_buffer| vertex_buffer.release();
    if (state.pipeline) |pipeline| pipeline.release();
    if (state.uniform) |uniform| uniform.deinit();

    state.vertex_buffer = state.renderer.device.createBuffer(&.{
        .label = "Vertex Data",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
        .size = @sizeOf(@TypeOf(vertex_data)),
    }).?;

    state.renderer.queue.writeBuffer(state.vertex_buffer.?, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));

    const shader_desc = gpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader = state.renderer.device.createShaderModule(&.{ .next_in_chain = &shader_desc.chain }).?;
    defer shader.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        gpu.VertexAttribute{
            .shader_location = 0,
            .format = .float32x2,
            .offset = 0,
        },
    };

    const vertex_layouts = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout{
            .array_stride = @sizeOf(@Vector(2, f32)),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
            .step_mode = .instance,
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

    state.uniform = Uniform.init(state.renderer.device);
    const size: [2]f32 = blk: {
        const width, const height = state.window.size();
        break :blk .{ @floatFromInt(width), @floatFromInt(height) };
    };

    state.renderer.queue.writeBuffer(state.uniform.?.buffer, 0, &size, @sizeOf(@TypeOf(size)));

    const layout = state.renderer.device.createPipelineLayout(&.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &.{state.uniform.?.layout},
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

    state.pipeline = state.renderer.device.createRenderPipeline(&.{
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

pub const Uniform = struct {
    layout: *gpu.BindGroupLayout,
    buffer: *gpu.Buffer,
    group: *gpu.BindGroup,

    pub fn init(device: *gpu.Device) Uniform {
        const buffer = device.createBuffer(&.{
            .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.uniform,
            .size = 2 * @sizeOf(f32),
        }).?;
        errdefer buffer.release();

        const layouts = [_]gpu.BindGroupLayoutEntry{
            gpu.BindGroupLayoutEntry{
                .binding = 0,
                .visibility = gpu.ShaderStage.vertex,
                .buffer = .{ .@"type" = .uniform, .min_binding_size = 2 * @sizeOf(f32) },
            },
        };

        const layout = device.createBindGroupLayout(&.{
            .entry_count = layouts.len,
            .entries = &layouts,
        }).?;
        errdefer layout.release();

        const bindings = [_]gpu.BindGroupEntry{
            gpu.BindGroupEntry{
                .binding = 0,
                .buffer = buffer,
                .size = 2 * @sizeOf(f32),
            },
        };

        const group = device.createBindGroup(&.{
            .layout = layout,
            .entry_count = 1,
            .entries = &bindings,
        }).?;
        errdefer group.release();

        return .{
            .layout = layout,
            .buffer = buffer,
            .group = group,
        };
    }

    pub fn deinit(uniform: *const Uniform) void {
        uniform.group.release();
        uniform.layout.release();
        uniform.buffer.release();
    }
};
