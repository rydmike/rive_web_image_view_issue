// Draws the bound texture on one square: two triangles from the vertex index, clip space x 0.1 to 0.9 and
// y -0.4 to 0.4, which is artboard x 220 to 380 and y 120 to 280 on the 400 x 400 canvas. It reads level 0 only,
// since an image's lower mip levels may be empty to a script.

@group(0) @binding(0) var picture: texture_2d<f32>;
@group(0) @binding(1) var pictureSampler: sampler;

struct VertexOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(0.0, 1.0),
    );
    let corner = corners[index];
    var o: VertexOut;
    o.clip = vec4<f32>(mix(0.1, 0.9, corner.x), mix(0.4, -0.4, corner.y), 0.0, 1.0);
    o.uv = corner;
    return o;
}

@fragment
fn fs_main(i: VertexOut) -> @location(0) vec4<f32> {
    return textureSampleLevel(picture, pictureSampler, i.uv, 0.0);
}
