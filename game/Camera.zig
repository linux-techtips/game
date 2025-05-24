const Event = @import("Engine").Event;

const std = @import("std");
const zlm = @import("zlm");
const gpu = @import("gpu");

const Camera = @This();

const sensitivity = 5;
const speed: @Vector(3, f32) = @splat(35);

pos: @Vector(3, f32),
eul: struct { yaw: f32 = -90, pitch: f32 = 0 },

right: @Vector(3, f32) = @splat(0),
dir: @Vector(3, f32) = .{ 0, 0, -1 },
up: @Vector(3, f32) = .{ 0, 1, 0 },

fn vec4(vec: @Vector(3, f32)) zlm.Vec {
    return .{ vec[0], vec[1], vec[2], 0 };
}

fn vec3(vec: @Vector(4, f32)) @Vector(3, f32) {
    return .{ vec[0], vec[1], vec[2] };
}

pub fn matrix(cam: *const Camera) zlm.Mat {
    return zlm.lookAtLh(vec4(cam.pos), vec4(cam.pos + cam.dir), vec4(cam.up));
}

pub fn move(cam: *Camera, key: Event.Key, dt: f32) void {
    const veloc = speed * @as(@Vector(3, f32), @splat(dt));

    if (key == .d) cam.pos += -cam.right * veloc;
    if (key == .a) cam.pos -= -cam.right * veloc;

    if (key == .w) cam.pos += cam.dir * veloc;
    if (key == .s) cam.pos -= cam.dir * veloc;

    cam.pos[1] = 0;

    std.debug.print("x: {d:.2} z: {d:.2}\n", .{ cam.pos[0], cam.pos[2] });
}

pub fn look(cam: *Camera, x: f32, y: f32, dt: f32) void {
    cam.eul.yaw += x * sensitivity * dt;
    cam.eul.pitch += y * sensitivity * dt;
    cam.eul.pitch = std.math.clamp(cam.eul.pitch, -89, 89);

    const psin, const pcos = zlm.sincos(std.math.degreesToRadians(cam.eul.pitch));
    const ysin, const ycos = zlm.sincos(std.math.degreesToRadians(cam.eul.yaw));

    cam.dir = vec3(zlm.normalize3(.{
        ycos * pcos,
        psin,
        ysin * pcos,
        0,
    }));

    cam.right = vec3(zlm.normalize3(zlm.cross3(vec4(cam.dir), vec4(cam.up))));
    cam.up = vec3(zlm.normalize3(zlm.cross3(vec4(cam.right), vec4(cam.dir))));

    std.debug.print("yaw: {d:.2} pitch: {d:.2}\n", .{ cam.eul.yaw, cam.eul.pitch });
}

pub const Projection = struct {
    aspect: f32,
    near: f32 = 0.01,
    far: f32 = 100,
    fov: f32 = 45,

    pub fn init(width: u32, height: u32, near: f32, far: f32, fov: f32) Projection {
        return .{
            .aspect = @floatFromInt(width / height),
            .near = near,
            .far = far,
            .fov = std.math.degreesToRadians(fov),
        };
    }

    pub fn matrix(proj: *const Projection) zlm.Mat {
        return zlm.perspectiveFovLh(proj.fov, proj.aspect, proj.near, proj.far);
    }

    pub fn resize(proj: *Projection, width: u32, height: u32) void {
        proj.aspect = @floatFromInt(width / height);
    }
};

pub const Uniform = struct {
    bindgroup: *gpu.BindGroup,
    layout: *gpu.BindGroupLayout,
    buffer: *gpu.Buffer,

    pub fn init(device: *gpu.Device) Uniform {
        const buffer = device.createBuffer(&.{
            .usage = gpu.BufferUsage.copy_dst | gpu.BufferUsage.uniform,
            .size = @sizeOf(zlm.Mat),
        }).?;
        errdefer buffer.release();

        const layout = device.createBindGroupLayout(&.{
            .entry_count = 1,
            .entries = &.{
                gpu.BindGroupLayoutEntry{
                    .binding = 0,
                    .visibility = gpu.ShaderStage.vertex,
                    .buffer = .{
                        .type = .uniform,
                        .min_binding_size = @sizeOf(zlm.Mat),
                    },
                },
            },
        }).?;
        errdefer layout.release();

        const bindgroup = device.createBindGroup(&.{
            .layout = layout,
            .entry_count = 1,
            .entries = &.{gpu.BindGroupEntry{
                .binding = 0,
                .buffer = buffer,
                .size = @sizeOf(zlm.Mat),
            }},
        }).?;
        errdefer bindgroup.release();

        return Uniform{
            .bindgroup = bindgroup,
            .layout = layout,
            .buffer = buffer,
        };
    }

    pub fn update(uniform: *const Uniform, queue: *gpu.Queue, cam: Camera, proj: Camera.Projection) void {
        const view = zlm.mul(cam.matrix(), proj.matrix());
        // _ = proj;
        // const view = cam.matrix();
        queue.writeBuffer(uniform.buffer, 0, &view, @sizeOf(zlm.Mat));
    }

    pub fn deinit(uniform: *const Uniform) void {
        uniform.bindgroup.release();
        uniform.buffer.release();
        uniform.layout.release();
    }
};
