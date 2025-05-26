struct VertexInput {
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec3f,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
    @location(1) normal: vec3f,
}

struct Uniform {
    model: mat4x4f,
};

@group(0) @binding(0) var<uniform> cam: mat4x4f;
@group(1) @binding(0) var<uniform> model: mat4x4f;

@vertex
fn vert(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    out.position = cam * model * vec4f(in.position, 1.0);
    out.color = in.color;
    out.normal = (model * vec4f(in.normal, 0.0)).xyz;

    return out;
}

@fragment
fn frag(in: VertexOutput) -> @location(0) vec4f {
    let linear = pow(in.color, vec3f(2.2));
    return vec4f(linear, 1.0);
}
