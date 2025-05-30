const std = @import("std");
const gpu = @import("gpu");

const System = @This();
const Card = extern struct {
    pos: @Vector(3, f32),
    rot: f32 = 0,
};

cards: std.ArrayList(Card),

pub fn init(_: *const Engine) !System {
    return .{
        .cards = undefined,
    };
}

pub fn loaded(_: *System) void {}

pub fn update(_: *System, _: *const Engine) void {}

pub fn render(system: *System, renderer: *Renderer, camera: Camera.Uniform) void {
    _ = system;
    const vertex_data = [_]Card{
        .{ .pos = .{ 0, 0, 4 } },
    };

    const uni_buffer = renderer.device.createBuffer(&gpu.BufferDescriptor{
        .label = "Uniform Buffer",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.uniform,
        .size = @sizeOf(@Vector(4, f32)),
    }).?;
    defer uni_buffer.release();

    const vertex_buffer = renderer.device.createBuffer(&gpu.BufferDescriptor{
        .label = "Vertex Buffer",
        .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.vertex,
        .size = @sizeOf(@TypeOf(vertex_data)),
    }).?;
    defer vertex_buffer.release();

    const color: @Vector(4, f32) = .{ 0.5, 0.2, 0.2, 0.5 };
    renderer.queue.writeBuffer(uni_buffer, 0, &color, @sizeOf(@Vector(4, f32)));
    renderer.queue.writeBuffer(vertex_buffer, 0, &vertex_data, vertex_buffer.getSize());

    const shader_desc = gpu.ShaderModuleWGSLDescriptor{
        .chain = .{ .s_type = .shader_module_wgsl_descriptor },
        .code = @embedFile("shaders/main.wgsl"),
    };

    const shader = renderer.device.createShaderModule(&.{ .next_in_chain = &shader_desc.chain }).?;
    defer shader.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        gpu.VertexAttribute{
            .shader_location = 0,
            .format = .float32x4,
            .offset = 0,
        },
    };

    const vertex_layouts = [_]gpu.VertexBufferLayout{
        gpu.VertexBufferLayout{
            .array_stride = @sizeOf(Card),
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

    const bind_layout_entries = [_]gpu.BindGroupLayoutEntry{
        gpu.BindGroupLayoutEntry{ .binding = 0, .visibility = gpu.ShaderStage.fragment, .buffer = .{
            .type = .uniform,
        } },
    };

    const bind_layout = renderer.device.createBindGroupLayout(&.{
        .entry_count = bind_layout_entries.len,
        .entries = &bind_layout_entries,
    }).?;
    defer bind_layout.release();

    const bind_group_entries = [_]gpu.BindGroupEntry{
        gpu.BindGroupEntry{
            .binding = 0,
            .buffer = uni_buffer,
            .size = uni_buffer.getSize(),
        },
    };

    const bind_group = renderer.device.createBindGroup(&.{
        .layout = bind_layout,
        .entry_count = bind_group_entries.len,
        .entries = &bind_group_entries,
    }).?;
    defer bind_group.release();

    const pipeline_layout = renderer.device.createPipelineLayout(&.{
        .bind_group_layout_count = 2,
        .bind_group_layouts = &.{ camera.layout, bind_layout },
    }).?;
    defer pipeline_layout.release();

    const pipeline = renderer.device.createRenderPipeline(&.{
        .layout = pipeline_layout,
        .vertex = vertex_state,
        .fragment = &fragment_state,
        .depth_stencil = &depth_stencil_state,
        .primitive = .{},
        .multisample = .{},
    }).?;
    defer pipeline.release();

    const frame = renderer.beginFrame();
    defer renderer.endFrame(&frame);

    frame.render_pass.setPipeline(pipeline);
    frame.render_pass.setVertexBuffer(0, vertex_buffer, 0, vertex_buffer.getSize());
    frame.render_pass.setBindGroup(0, camera.bindgroup, 0, null);
    frame.render_pass.setBindGroup(1, bind_group, 0, null);
    frame.render_pass.draw(6, vertex_data.len, 0, 0);
}

pub fn evented(system: *System, event: *const Event) void {
    _ = system;
    _ = event;
}

pub fn deinit(system: *System) void {
    system.cards.deinit();
}

const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");
const Engine = @import("Engine");
const Event = Engine.Event;
