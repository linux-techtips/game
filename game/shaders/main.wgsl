struct VertexIn {
    @builtin(vertex_index) idx: u32,
    @location(0) origin: vec2f,
}

struct VertexOut {
    @builtin(position) position: vec4f,
    @location(0) local: vec2f,
}

struct Uniform {
    viewport: vec2f,
};

@group(0) @binding(0) var<uniform> uniform: Uniform;

const size: vec2<f32> = vec2f(60, 90);

@vertex
fn vert(in: VertexIn) -> VertexOut {
    var points = array(
        vec2f(-1, -1),
        vec2f( 1, -1),
        vec2f(-1,  1),
        vec2f(-1,  1),
        vec2f( 1, -1),
        vec2f( 1,  1),
    );

    let local_pos = points[in.idx] * size;
    let point_off = points[in.idx] * (size / (uniform.viewport / 2.0));

    var out: VertexOut;
    out.position = vec4f(in.origin + point_off, 0, 1);
    out.local = local_pos;

    return out;
}


fn sd_rounded_rect(pos: vec2f, border: vec2f, radius: f32) -> f32 {
    let q = abs(pos) - border + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2f(0.0))) - radius;
}


@fragment
fn frag(in: VertexOut) -> @location(0) vec4f {
    let rect = sd_rounded_rect(in.local, size, 15.0);
    let alpha = 1.0 - smoothstep(0.0, 1.0, rect);
    return vec4f(1.0, 1.0, 1.0, alpha);
}
