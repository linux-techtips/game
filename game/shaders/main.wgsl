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
    time: f32,
};

@group(0) @binding(0) var<uniform> cam: mat4x4f;
@group(1) @binding(0) var<uniform> uni: Uniform;

@vertex
fn vert(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    out.position = cam * uni.model * vec4f(in.position, 1.0);
    out.color = in.color;
    out.normal = (uni.model * vec4f(in.normal, 0.0)).xyz;

    return out;
}

@fragment
fn frag(in: VertexOutput) -> @location(0) vec4f {
    let normal = normalize(in.normal);
    let light_color1 = vec3f(1.0, 0.9, 0.6);
    let light_color2 = vec3f(0.6, 0.9, 1.0);

    let shading1 = max(0.0, dot(vec3f(0.5, -0.9, 0.1), normal));
    let shading2 = max(0.0, dot(vec3f(0.2, 0.4, 0.3), normal));

    let shading = shading1 * light_color1 + shading2 * light_color2;

    let color = in.color * shading;
    let linear = pow(color, vec3f(2.2));
    return vec4f(color, 1.0);
}
