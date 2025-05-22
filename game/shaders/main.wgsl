struct VertexInput {
    @location(0) position: vec3f,
    @location(1) color: vec3f,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
}

struct Uniform {
    color: vec4f,
    time: f32,
    ratio: f32,
};

@group(0) @binding(0) var<uniform> uniform: Uniform;

@vertex
fn vert(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    var angle = uniform.time;
    var S = sin(angle);
    var C = cos(angle);

    let R1 = transpose(mat3x3f(
        C, S, 0.0,
        -S, C, 0.0,
        0.0, 0.0, 1.0,
    ));

    angle = 3.0 * 3.1459 / 4;
    S = sin(angle);
    C = cos(angle);
    let R2 = transpose(mat3x3f(
        1.0, 0.0, 0.0,
        0.0, C, S,
        0, -S, C
    ));

    let position = R2 * R1 * in.position;

	out.position = vec4f(position.x, position.y * uniform.ratio, position.z * 0.5 + 0.5, 1.0);
    out.color = in.color;

    return out;
}

@fragment
fn frag(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uniform.color.rgb;
    let linear = pow(color, vec3f(2.2));
    return vec4f(linear, 1.0);
}
