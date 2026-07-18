renderer_push_water_molecule :: (renderer: *Renderer, sphere: Mesh_Asset, center: V3f) {
    oxygen_model := m4_translation(center) * m4_scale(.{ 0.65, 0.65, 0.65 });
    renderer_push_mesh(renderer, sphere, oxygen_model, .{ 0.85, 0.08, 0.05, 1.0 });

    oxygen_hydrogen_distance :: 1.15;
    hydrogen_x := oxygen_hydrogen_distance * 0.612217;
    hydrogen_z := oxygen_hydrogen_distance * 0.790689;
    hydrogen_scale := m4_scale(.{ 0.36, 0.36, 0.36 });
    hydrogen_a := center + .{ hydrogen_x, 0, hydrogen_z };
    hydrogen_b := center + .{ hydrogen_x, 0, -hydrogen_z };
    renderer_push_mesh(renderer, sphere, m4_translation(hydrogen_a) * hydrogen_scale, .{ 0.92, 0.94, 1.0, 1.0 });
    renderer_push_mesh(renderer, sphere, m4_translation(hydrogen_b) * hydrogen_scale, .{ 0.92, 0.94, 1.0, 1.0 });
}

renderer_render_game :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    renderer := *state.renderer;
    renderer_begin_instances(renderer);
    for row: 0..GRID_ROWS - 1 {
        for column: 0..GRID_COLUMNS - 1 {
            position := game_grid_position(cast(s32) column, cast(s32) row);
            model := m4_translation(position) * m4_scale(.{ 0.92, 0.35, 0.92 });
            renderer_push_mesh(renderer, state.store.cube_mesh, model, .{ 0.12, 0.32, 0.45, 1.0 });
        }
    }

    grid_width := cast(float32) GRID_COLUMNS * GRID_SPACING;
    left_edge := -grid_width * 0.5;
    right_edge := grid_width * 0.5;
    travel_distance := grid_width + 9.0;
    time := cast(float32) state.tick_count * input.simulation_delta_seconds;
    for state.water_molecules {
        traveled := time * WATER_SPEED + it.start_offset;
        wrapped_distance := traveled - cast(float32) (cast(s32) (traveled / travel_distance)) * travel_distance;
        center := game_grid_position(GRID_COLUMNS - 1, it.lane);
        center.x = right_edge + 4.5 - wrapped_distance;
        center.y = WATER_HEIGHT;
        if center.x >= left_edge - 4.5 {
            renderer_push_water_molecule(renderer, state.store.sphere_mesh, center);
        }
    }

    aspect_ratio := cast(float32) input.framebuffer_size_pixels.x / cast(float32) input.framebuffer_size_pixels.y;
    camera: Render_Camera = .{};
    camera.view_projection = camera_view_projection(state.camera, aspect_ratio);
    renderer_draw(renderer, platform, camera, xx input.framebuffer_size_pixels.x, xx input.framebuffer_size_pixels.y);
}

game_capture_frame :: (state: *Game_State, platform: *Platform) {
    pixel_count := cast(u64) state.renderer.capture_width * state.renderer.capture_height;
    array_resize(*state.capture_rgba, xx (pixel_count * 4));
    if !renderer_copy_rgba(*state.renderer, platform, state.capture_rgba) {
        return;
    }
    array_resize(*state.capture_pixels, xx pixel_count);
    for y: 0..state.renderer.capture_height - 1 {
        for x: 0..state.renderer.capture_width - 1 {
            source_index := (y * state.renderer.capture_width + x) * 4;
            destination_index := y * state.renderer.capture_width + x;
            state.capture_pixels[destination_index] = .{
                state.capture_rgba[source_index + 0],
                state.capture_rgba[source_index + 1],
                state.capture_rgba[source_index + 2],
                state.capture_rgba[source_index + 3],
            };
        }
    }
    max_qoi_bytes := qoi_encoded_max_size(pixel_count);
    array_resize(*state.capture_qoi, xx max_qoi_bytes);
    info: Qoi_Image_Info = .{
        width = state.renderer.capture_width,
        height = state.renderer.capture_height,
        channels = 4,
        colorspace = 0,
    };
    qoi_bytes, encoded := qoi_encode(info, state.capture_pixels, state.capture_qoi);
    if !encoded || !platform.system.write_file {
        return;
    }
    state.capture_qoi.count = xx qoi_bytes;
    path := tprint("captures/frame_%.qoi", state.capture_frame_index);
    if platform.system.write_file(.{ data = path.data, count = path.count }, state.capture_qoi) {
        state.capture_frame_index += 1;
    }
}
