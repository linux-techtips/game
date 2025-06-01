struct VertexOut {
    @builtin(position) pos: vec4f,
    @location(0) color: vec3f,
};

@vertex
fn vert(@location(0) pos: vec2f, @location(1) color: vec3f) -> VertexOut {
    var out: VertexOut;
    out.pos = vec4f(pos, 0, 1);
    out.color = color;

    return out;
}

@fragment
fn frag(@location(0) color: vec3f) -> @location(0) vec4f {
    return vec4f(color, 1);
}
