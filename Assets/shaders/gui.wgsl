struct Gui_Uniform {
    framebuffer_size_pixels: vec2f,
    padding: vec2f,
}

struct Gui_Instance {
    position_pixels: vec2f,
    size_pixels: vec2f,
    color: vec4f,
    uv_rect: vec4f,
    kind: u32,
    outline_width_pixels: f32,
    sort_z: f32,
    padding0: u32,
}

struct Vertex_Output {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @interpolate(flat) @location(1) instance_index: u32,
}

@group(0) @binding(0) var<uniform> gui_uniform: Gui_Uniform;
@group(0) @binding(1) var<storage, read> gui_instances: array<Gui_Instance>;
@group(0) @binding(2) var font_texture: texture_2d<f32>;
@group(0) @binding(3) var font_sampler: sampler;

@vertex
fn vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
    let corners = array<vec2f, 6>(
        vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0),
        vec2f(0.0, 0.0), vec2f(1.0, 1.0), vec2f(0.0, 1.0),
    );
    let instance = gui_instances[instance_index];
    let corner = corners[vertex_index];
    let pixel_position = instance.position_pixels + corner * instance.size_pixels;
    let clip_position = vec2f(
        pixel_position.x / gui_uniform.framebuffer_size_pixels.x * 2.0 - 1.0,
        1.0 - pixel_position.y / gui_uniform.framebuffer_size_pixels.y * 2.0,
    );
    var output: Vertex_Output;
    output.position = vec4f(clip_position, 0.0, 1.0);
    output.uv = instance.uv_rect.xy + corner * instance.uv_rect.zw;
    output.instance_index = instance_index;
    return output;
}

fn median(value: vec3f) -> f32 {
    return max(min(value.r, value.g), min(max(value.r, value.g), value.b));
}

@fragment
fn fs(input: Vertex_Output) -> @location(0) vec4f {
    let instance = gui_instances[input.instance_index];

    let signed_distance = median(textureSample(font_texture, font_sampler, input.uv).rgb) - 0.5;
    let pixel_range = max(fwidth(signed_distance), 0.00001);
    let fill_alpha = clamp(signed_distance / pixel_range + 0.5, 0.0, 1.0);
    let outline_distance = signed_distance + instance.outline_width_pixels * pixel_range;
    let outline_alpha = clamp(outline_distance / pixel_range + 0.5, 0.0, 1.0);
    let fill = vec4f(instance.color.rgb, instance.color.a * fill_alpha);
    let outline = vec4f(0.0, 0.0, 0.0, instance.color.a * (outline_alpha - fill_alpha));
    if (instance.kind == 0u) {
        return instance.color;
    }
    return outline + fill;
}
