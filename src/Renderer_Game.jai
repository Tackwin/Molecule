renderer_push_water_molecule :: (renderer: *Renderer, sphere: Mesh_Asset, center: V3f) {
    oxygen_model := m4_translation(center) * m4_scale(.{ 0.65, 0.65, 0.65 });
    renderer_push_mesh(renderer, sphere, oxygen_model, .{ 0.85, 0.08, 0.05, 1.0 });

    oxygen_hydrogen_distance :: 1.15;
    hydrogen_x := oxygen_hydrogen_distance * 0.612217;
    hydrogen_y := oxygen_hydrogen_distance * 0.790689;
    hydrogen_scale := m4_scale(.{ 0.36, 0.36, 0.36 });
    hydrogen_a := center + .{ hydrogen_x, hydrogen_y, 0 };
    hydrogen_b := center + .{ hydrogen_x, -hydrogen_y, 0 };
    renderer_push_mesh(renderer, sphere, m4_translation(hydrogen_a) * hydrogen_scale, .{ 0.92, 0.94, 1.0, 1.0 });
    renderer_push_mesh(renderer, sphere, m4_translation(hydrogen_b) * hydrogen_scale, .{ 0.92, 0.94, 1.0, 1.0 });
}

renderer_render_gui_demo :: (state: *Game_State, input: *Frame_Input) {
    screen_width := cast(float32) input.framebuffer_size_pixels.x;
    screen_height := cast(float32) input.framebuffer_size_pixels.y;
    gui_panel(*state.gui, .{ 0, 0 }, .{ screen_width, screen_height }, .{ 0.01, 0.025, 0.055, 0.94 }, 10);
    gui_label(*state.gui, "GUI widget and layout demo", .{ 34, 26 }, 26, .{ 0.82, 0.93, 1, 1 }, 12, 1);
    gui_label(*state.gui, "F8 closes this screen", .{ 36, 59 }, 13, .{ 0.52, 0.66, 0.82, 1 }, 12);

    left_panel_position := V2f.{ 34, 96 };
    right_panel_position := V2f.{ 382, 96 };
    panel_size := V2f.{ 314, screen_height - 128 };
    gui_panel(*state.gui, left_panel_position, panel_size, .{ 0.035, 0.08, 0.15, 0.98 }, 11);
    gui_panel(*state.gui, right_panel_position, panel_size, .{ 0.035, 0.08, 0.15, 0.98 }, 11);

    gui_begin_column(*state.gui, left_panel_position + .{ 18, 18 }, 12, .{ 8, 9 });
    gui_label_flow(*state.gui, "Typography and buttons", 18, .{ 0.82, 0.92, 1, 1 }, 1);
    gui_label_flow(*state.gui, "Prepared text measures before placement.", 12, .{ 0.62, 0.73, 0.88, 1 });
    gui_separator_flow(*state.gui, 278);
    gui_push_row(*state.gui);
    gui_button_flow(*state.gui, "primary", "Primary");
    gui_button_flow(*state.gui, "secondary", "Secondary");
    gui_pop_layout(*state.gui);
    gui_checkbox_flow(*state.gui, "checkbox", "Enable a sample option", *state.gui_demo_checkbox);
    gui_label_flow(*state.gui, "Nested row / column layout", 14, .{ 0.69, 0.82, 1, 1 });
    gui_push_row(*state.gui);
    gui_push_column(*state.gui);
    gui_button_flow(*state.gui, "left_a", "A");
    gui_button_flow(*state.gui, "left_b", "B");
    gui_pop_layout(*state.gui);
    gui_push_column(*state.gui);
    gui_button_flow(*state.gui, "right_c", "C");
    gui_button_flow(*state.gui, "right_d", "D");
    gui_pop_layout(*state.gui);
    gui_pop_layout(*state.gui);
    gui_pop_layout(*state.gui);

    gui_begin_column(*state.gui, right_panel_position + .{ 18, 18 }, 12, .{ 8, 9 });
    gui_label_flow(*state.gui, "Continuous controls", 18, .{ 0.82, 0.92, 1, 1 }, 1);
    gui_label_flow(*state.gui, "Drag the slider", 12, .{ 0.62, 0.73, 0.88, 1 });
    gui_separator_flow(*state.gui, 278);
    gui_label_flow(*state.gui, "Sample value", 14, .{ 0.69, 0.82, 1, 1 });
    gui_slider_float_flow(*state.gui, "sample_slider", *state.gui_demo_slider, 0, 1, 278);
    gui_label_flow(*state.gui, tprint("%.2f", state.gui_demo_slider), 14, .{ 0.72, 0.86, 1, 1 });
    gui_label_flow(*state.gui, "Progress bar", 14, .{ 0.69, 0.82, 1, 1 });
    progress := cast(float32) (state.tick_count % 180) / 179.0;
    gui_progress_bar_flow(*state.gui, 278, progress);
    gui_push_row(*state.gui);
    if gui_button_flow(*state.gui, "set_low", "25%") {
        state.gui_demo_slider = 0.25;
    }
    if gui_button_flow(*state.gui, "set_high", "75%") {
        state.gui_demo_slider = 0.75;
    }
    gui_pop_layout(*state.gui);
    gui_pop_layout(*state.gui);
}

renderer_render_game :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    renderer := *state.renderer;
    renderer_begin_instances(renderer);
    for row: 0..GRID_ROWS - 1 {
        for column: 0..GRID_COLUMNS - 1 {
            position := game_grid_position(cast(s32) column, cast(s32) row);
            model := m4_translation(position) * m4_scale(.{ 0.92, 0.92, 0.35 });
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
        center.z = WATER_HEIGHT;
        if center.x >= left_edge - 4.5 {
            renderer_push_water_molecule(renderer, state.store.sphere_mesh, center);
        }
    }

    aspect_ratio := cast(float32) input.framebuffer_size_pixels.x / cast(float32) input.framebuffer_size_pixels.y;
    camera: Render_Camera = .{};
    camera.view_projection = camera_view_projection(state.camera, aspect_ratio);
    if state.gui_demo_open {
        renderer_render_gui_demo(state, input);
    } else {
        gui_quad(*state.gui, .{ 12, 12 }, .{ 280, 102 }, .{ 0.02, 0.05, 0.1, 0.88 }, 1);
        gui_begin_column(*state.gui, .{ 22, 21 }, 2);
        gui_label_flow(*state.gui, "Molecule", 20, .{ 0.82, 0.92, 1, 1 }, 1);
        gui_label_flow(*state.gui, "ZQSD / arrows: move    wheel: zoom", 12, .{ 0.65, 0.75, 0.9, 1 });
        gui_label_flow(*state.gui, "F8: GUI demo", 12, .{ 0.65, 0.75, 0.9, 1 });
        gui_push_row(*state.gui);
        if gui_button_flow(*state.gui, "reset_camera", "Reset camera") {
            camera_init(*state.camera);
        }
        gui_pop_layout(*state.gui);
        gui_pop_layout(*state.gui);
    }
    renderer_draw(
        renderer,
        platform,
        camera,
        *state.gui,
        xx input.framebuffer_size_pixels.x,
        xx input.framebuffer_size_pixels.y,
        input.capture_frame
    );
    gui_end_frame(*state.gui);
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
