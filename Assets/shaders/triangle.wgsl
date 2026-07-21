struct Camera_Data {
    view_projection: mat4x4<f32>,
    position: vec3f,
    cavity_strength: f32,
    cavity_normal_threshold: f32,
    cavity_width: f32,
    cavity_fade_start: f32,
    cavity_fade_end: f32,
    cavity_minimum_projected_width: f32,
    padding_0: f32,
    padding_1: f32,
    padding_2: f32,
}

struct Geometry_Vertex {
    position: vec3f,
    position_padding: f32,
    uv: vec2f,
    uv_padding: vec2f,
}

struct Geometry_Triangle {
    normal: vec3f,
    normal_padding: f32,
    edge_cavity: vec3f,
    cavity_padding: f32,
}

struct Render_Instance {
    model: mat4x4<f32>,
    color: vec4f,
    vertex_offset: u32,
    triangle_offset: u32,
    flags: u32,
    padding: u32,
}

struct Vertex_Output {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
    @location(1) @interpolate(flat) normal: vec3f,
    @location(2) uv: vec2f,
    @location(3) @interpolate(flat) flags: u32,
    @location(4) barycentric: vec3f,
    @location(5) @interpolate(flat) edge_cavity: vec3f,
    @location(6) @interpolate(flat) edge_altitude: vec3f,
    @location(7) world_position: vec3f,
}

@group(0) @binding(0) var<uniform> camera: Camera_Data;
@group(0) @binding(1) var<storage, read> geometry_vertices: array<Geometry_Vertex>;
@group(0) @binding(2) var<storage, read> instances: array<Render_Instance>;
@group(0) @binding(3) var<storage, read> geometry_triangles: array<Geometry_Triangle>;
@group(0) @binding(4) var palette_texture: texture_2d<f32>;
@group(0) @binding(5) var palette_sampler: sampler;

@vertex
fn vs(
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
) -> Vertex_Output {
    let instance = instances[instance_index];
    let local_triangle_index = vertex_index / 3u;
    let local_vertex_index = vertex_index % 3u;
    let triangle = geometry_triangles[instance.triangle_offset + local_triangle_index];
    let triangle_vertex_offset = instance.vertex_offset + local_triangle_index * 3u;
    let local_p0 = geometry_vertices[triangle_vertex_offset + 0u].position;
    let local_p1 = geometry_vertices[triangle_vertex_offset + 1u].position;
    let local_p2 = geometry_vertices[triangle_vertex_offset + 2u].position;
    let world_p0 = (instance.model * vec4f(local_p0, 1.0)).xyz;
    let world_p1 = (instance.model * vec4f(local_p1, 1.0)).xyz;
    let world_p2 = (instance.model * vec4f(local_p2, 1.0)).xyz;
    let world_positions = array<vec3f, 3>(world_p0, world_p1, world_p2);
    let barycentrics = array<vec3f, 3>(
        vec3f(1.0, 0.0, 0.0),
        vec3f(0.0, 1.0, 0.0),
        vec3f(0.0, 0.0, 1.0),
    );
    let double_area = length(cross(local_p1 - local_p0, local_p2 - local_p0));
    let edge_altitude = vec3f(
        double_area / max(length(local_p2 - local_p1), 0.000001),
        double_area / max(length(local_p0 - local_p2), 0.000001),
        double_area / max(length(local_p1 - local_p0), 0.000001),
    );
    let vertex = geometry_vertices[instance.vertex_offset + vertex_index];
    let world_position = world_positions[local_vertex_index];
    var output: Vertex_Output;
    output.position = camera.view_projection * vec4f(world_position, 1.0);
    output.color = instance.color.rgb;
    output.normal = normalize(cross(world_p1 - world_p0, world_p2 - world_p0));
    output.uv = vertex.uv;
    output.flags = instance.flags;
    output.barycentric = barycentrics[local_vertex_index];
    output.edge_cavity = triangle.edge_cavity;
    output.edge_altitude = edge_altitude;
    output.world_position = world_position;
    return output;
}

@fragment
fn fs(input: Vertex_Output) -> @location(0) vec4f {
    let light_direction = normalize(vec3f(0.4, 0.7, 0.5));
    let lighting = 0.25 + 0.75 * max(dot(input.normal, light_direction), 0.0);
    let palette_color = textureSample(palette_texture, palette_sampler, vec2f(input.uv.x, 1.0 - input.uv.y)).rgb;
    let material_color = select(input.color, input.color * palette_color, (input.flags & 0x00000001u) != 0u);
    let lit_color = material_color * lighting;

    let edge_distances = input.barycentric * input.edge_altitude;
    let normal_threshold = clamp(camera.cavity_normal_threshold, 0.0, 0.9999);
    let half_width = max(camera.cavity_width * 0.5, 0.0);
    let minimum_projected_width = max(camera.cavity_minimum_projected_width, 0.0);
    var strongest_contribution = 0.0;
    for (var edge_index = 0u; edge_index < 3u; edge_index += 1u) {
        let edge_distance = edge_distances[edge_index];
        let signed_dihedral = input.edge_cavity[edge_index];
        let cavity_amount = clamp(
            (abs(signed_dihedral) - normal_threshold) / (1.0 - normal_threshold),
            0.0,
            1.0,
        );
        let antialias_width = max(fwidth(edge_distance), 0.000001);
        let edge_mask = 1.0 - smoothstep(
            max(half_width - antialias_width, 0.0),
            half_width + antialias_width,
            edge_distance,
        );
        let projected_width = camera.cavity_width / antialias_width;
        let minification_fade = smoothstep(
            minimum_projected_width * 0.5,
            max(minimum_projected_width, 0.000001),
            projected_width,
        );
        let contribution = sign(signed_dihedral) * cavity_amount * edge_mask * minification_fade;
        if abs(contribution) > abs(strongest_contribution) {
            strongest_contribution = contribution;
        }
    }
    let fade_end = max(camera.cavity_fade_end, camera.cavity_fade_start + 0.001);
    let camera_distance = distance(camera.position, input.world_position);
    let distance_fade = 1.0 - smoothstep(camera.cavity_fade_start, fade_end, camera_distance);
    let cavity_strength = clamp(camera.cavity_strength * abs(strongest_contribution) * distance_fade, 0.0, 1.0);
    let cavity_color = select(vec3f(0.0), vec3f(1.0), strongest_contribution >= 0.0);
    return vec4f(mix(lit_color, cavity_color, cavity_strength), 1.0);
}
