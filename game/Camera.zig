const std = @import("std");
const gpu = @import("gpu");
const zlm = @import("zlm");

const Camera = @This();

const dir: @Vector(3, f32) = .{ 0, 0, 1 };
const up: @Vector(3, f32) = .{ 0, 1, 0 };

const near: f32 = 0.01;
const far: f32 = 100;
const fov: f32 = 45;

pos: struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 } = .{},
rot: struct { r: f32 = 0, p: f32 = 0, y: f32 = 0 } = .{},

texture: *gpu.Texture,

pub fn view(camera: *const Camera) zlm.Mat {
    return zlm.lookAtLh(vec4(camera.pos), vec4(camera.pos + dir), vec4(up));
}

pub fn proj(camera: *const Camera) zlm.Mat {
    const height = 2 * std.math.tan(fov / 2);
    const width = height * camera.aspect();

    return zlm.orthographicLh(width, height, near, far);
}

pub fn aspect(camera: *const Camera) f32 {
    const height: f32 = @floatFromInt(camera.texture.getHeight());
    const width: f32 = @floatFromInt(camera.texture.getWidth());

    return width / height;
}

fn vec4(vec: @Vector(3, f32)) zlm.Vec {
    return .{ vec[0], vec[1], vec[2], 0 };
}
