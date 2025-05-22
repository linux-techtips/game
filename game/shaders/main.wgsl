struct VertexInput {
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec3f,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
}

struct Uniform {
    proj: mat4x4f,
    view: mat4x4f,
    model: mat4x4f,
    color: vec4f,
    time: f32,
};

@group(0) @binding(0) var<uniform> uni: Uniform;

@vertex
fn vert(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    out.position = uni.proj * uni.view * uni.model * vec4f(in.position, 1.0);
    out.color = in.color;

    return out;
}

@fragment
fn frag(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uni.color.rgb;
    let linear = pow(color, vec3f(2.2));
    return vec4f(color, 1.0);
}
