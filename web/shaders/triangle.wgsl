// Vertex pulling: vertex_index is the only input. There are no vertex buffers.

struct Vertex_Output {
  @builtin(position) position: vec4f,
  @location(0) color: vec3f,
}

@vertex
fn vs(@builtin(vertex_index) vertex_index: u32) -> Vertex_Output {
  let positions = array<vec2f, 3>(
    vec2f( 0.0,  0.65),
    vec2f(-0.65, -0.65),
    vec2f( 0.65, -0.65),
  );
  let colors = array<vec3f, 3>(
    vec3f(1.0, 0.25, 0.20),
    vec3f(0.20, 1.0, 0.45),
    vec3f(0.25, 0.55, 1.0),
  );

  var output: Vertex_Output;
  output.position = vec4f(positions[vertex_index], 0.0, 1.0);
  output.color = colors[vertex_index];
  return output;
}

@fragment
fn fs(input: Vertex_Output) -> @location(0) vec4f {
  return vec4f(input.color, 1.0);
}
