struct VertexInput {
    @location(0) position: vec3f,
    @location(1) color: vec3f,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
}

@group(0) @binding(0) var<uniform> time: f32;
@group(0) @binding(1) var<uniform> ratio: f32;

@vertex
fn vert(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

	out.position = vec4f(in.position.x, in.position.y * ratio, 0.0, 1.0);

    out.color = in.color;

    return out;
}

@fragment
fn frag(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(in.color, 1.0);
}
