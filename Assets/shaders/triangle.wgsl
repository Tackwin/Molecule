// Hot-reload verification marker.
struct Camera_Data {
    view_projection: mat4x4<f32>,
}

struct Geometry_Vertex {
    position: vec3f,
    position_padding: f32,
    normal: vec3f,
    normal_padding: f32,
}

struct Render_Instance {
    model: mat4x4<f32>,
    color: vec4f,
    vertex_offset: u32,
    padding0: u32,
    padding1: u32,
    padding2: u32,
}

struct Vertex_Output {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
    @location(1) normal: vec3f,
}

@group(0) @binding(0) var<uniform> camera: Camera_Data;
@group(0) @binding(1) var<storage, read> geometry_vertices: array<Geometry_Vertex>;
@group(0) @binding(2) var<storage, read> instances: array<Render_Instance>;

@vertex
fn vs(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> Vertex_Output {
    let instance = instances[instance_index];
    let vertex = geometry_vertices[instance.vertex_offset + vertex_index];
    let world_position = instance.model * vec4f(vertex.position, 1.0);
    var output: Vertex_Output;
    output.position = camera.view_projection * world_position;
    output.color = instance.color.rgb;
    output.normal = normalize((instance.model * vec4f(vertex.normal, 0.0)).xyz);
    return output;
}

@fragment
fn fs(input: Vertex_Output) -> @location(0) vec4f {
    let light_direction = normalize(vec3f(0.4, 0.7, 0.5));
    let lighting = 0.25 + 0.75 * max(dot(input.normal, light_direction), 0.0);
    return vec4f(input.color * lighting, 1.0);
}
