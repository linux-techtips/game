const CARD_ASPECT = vec2f(1.0, 1.5);

@group(1) @binding(0) var<uniform> color_override: vec4f;
@group(0) @binding(0) var<uniform> projection: mat4x4f;

struct VertexOut {
    @builtin(position) world: vec4f,
    @location(0) local: vec2f,
}

fn rot2d(pos: vec2f, angle: f32) -> vec2f {
    let c = cos(angle);
    let s = sin(angle);
    return vec2f(
        c * pos.x - s * pos.y,
        s * pos.x + c * pos.y,
    );
}

fn sd_rounded_rect(pos: vec2f, border: vec2f, radius: f32) -> f32 {
    let q = abs(pos) - border + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2f(0.0))) - radius;
}

@vertex
fn vert(@builtin(vertex_index) idx: u32, @location(0) card: vec4f) -> VertexOut {
    var points = array(
        vec2f(-1.0,  1.5),
        vec2f( 1.0,  1.5),
        vec2f(-1.0, -1.5),
        vec2f( 1.0,  1.5),
        vec2f(-1.0, -1.5),
        vec2f( 1.0, -1.5),
    );

    let pos = card.xyz;
    let rot = card.w;

    var out: VertexOut;
    out.local = points[idx].xy + pos.xy;
    out.world = projection * vec4f(rot2d(out.local, rot), pos.z, 1);

    return out;
}

@fragment
fn frag(@location(0) local: vec2f) -> @location(0) vec4f {
    let rect = sd_rounded_rect(local, CARD_ASPECT, 0.15);
    let alpha = 1.0 - smoothstep(-0.01, 0.01, rect);

    let color = mix(vec3f(1.0, 1.0, 1.0), color_override.rgb, color_override.a);
    return vec4f(color, alpha);
}
