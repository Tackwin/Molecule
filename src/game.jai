#import "Basic";
#import "platform";
#import "Algebra";
#import "Qoi";
#import "renderer";
#import "Store";
#import "GUI";
#import "Math";

GRID_COLUMNS :: 40;
GRID_ROWS :: 15;
GRID_SPACING :: 2.2;
WATER_MOLECULE_COUNT :: 100;
WATER_HEIGHT :: 2.1;
WATER_SPEED :: 0.05;
MOUSE_BUTTON_LEFT :: 1;
MOUSE_BUTTON_RIGHT :: 2;

Water_Molecule :: struct {
    lane: s32;
    start_offset: float32;
}

Camera :: struct {
    position: V3f;
    target: V3f;
    up: V3f;
    focal_length: float32;
    near_plane: float32;
    far_plane: float32;
    move_speed: float32;
    zoom_speed: float32;
    min_target_distance: float32;
    max_target_distance: float32;
}

camera_init :: (camera: *Camera) {
    camera.target = .{ 0, 0, 0 };
    camera.up = .{ 0, 0, 1 };
    camera.focal_length = 1.7320508;
    camera.near_plane = 0.1;
    camera.far_plane = 200.0;
    camera.move_speed = 10.0;
    camera.zoom_speed = 5.0;
    camera.min_target_distance = 8.0;
    camera.max_target_distance = 120.0;
    theta := 70.0 * (3.14159265358979323846 / 180.0);
    camera.position.z = xx sin(theta);
    camera.position.y = xx cos(theta);
    camera.position.x = 0;
    camera.position = normalize(camera.position) * 50;
}

camera_render_data :: (camera: Camera, aspect_ratio: float32, cavity: Cavity_Settings) -> Render_Camera {
    view := m4_look_at(camera.position, camera.target, camera.up);
    projection := m4_perspective(camera.focal_length, aspect_ratio, camera.near_plane, camera.far_plane);
    return .{
        view_projection = projection * view,
        position = camera.position,
        cavity_strength = cavity.strength,
        cavity_normal_threshold = cavity.normal_threshold,
        cavity_width = cavity.width,
        cavity_fade_start = cavity.fade_start,
        cavity_fade_end = cavity.fade_end,
        cavity_minimum_projected_width = cavity.minimum_projected_width,
    };
}

camera_ground_point_under_cursor :: (
    camera: Camera,
    mouse_position_pixels: V2i,
    framebuffer_size_pixels: V2i,
    ground_point: *V3f
) -> bool {
    if framebuffer_size_pixels.x <= 0 || framebuffer_size_pixels.y <= 0 {
        return false;
    }

    aspect_ratio := cast(float32) framebuffer_size_pixels.x / cast(float32) framebuffer_size_pixels.y;
    ndc_x := (2.0 * (cast(float32) mouse_position_pixels.x + 0.5) / cast(float32) framebuffer_size_pixels.x) - 1.0;
    ndc_y := 1.0 - (2.0 * (cast(float32) mouse_position_pixels.y + 0.5) / cast(float32) framebuffer_size_pixels.y);
    forward := normalize(camera.target - camera.position);
    if forward == V3f.{} {
        return false;
    }
    right := normalize(cross(forward, camera.up));
    up := cross(right, forward);
    ray_direction := normalize(
        forward +
        right * (ndc_x * aspect_ratio / camera.focal_length) +
        up * (ndc_y / camera.focal_length)
    );
    if ray_direction.z > -0.0001 && ray_direction.z < 0.0001 {
        return false;
    }

    distance_to_ground := -camera.position.z / ray_direction.z;
    if distance_to_ground < 0 {
        return false;
    }

    ground_point.* = camera.position + ray_direction * distance_to_ground;
    ground_point.z = 0;
    return true;
}

camera_move :: (camera: *Camera, input: *Frame_Input) {
    forward := camera.target - camera.position;
    forward.z = 0;
    forward = normalize(forward);
    right := normalize(cross(forward, .{ 0, 0, 1 }));
    movement: V3f = .{};
    if input.keyboard.down[KEY_MOVE_UP] {
        movement += forward;
    }
    if input.keyboard.down[KEY_MOVE_LEFT] {
        movement -= right;
    }
    if input.keyboard.down[KEY_MOVE_DOWN] {
        movement -= forward;
    }
    if input.keyboard.down[KEY_MOVE_RIGHT] {
        movement += right;
    }
    if movement == V3f.{} {
        return;
    }
    movement = normalize(movement) * (camera.move_speed * input.simulation_delta_seconds);
    camera.position += movement;
    camera.target += movement;
}

camera_zoom :: (camera: *Camera, wheel_steps: s32, platform: *Platform) {
    if wheel_steps == 0 {
        return;
    }
    to_camera := camera.position - camera.target;
    distance := length(to_camera);
    if distance == 0 {
        return;
    }
    distance -= cast(float32) wheel_steps * camera.zoom_speed;
    if distance < camera.min_target_distance {
        distance = camera.min_target_distance;
    }
    if distance > camera.max_target_distance {
        distance = camera.max_target_distance;
    }
    camera.position = camera.target + normalize(to_camera) * distance;
}

camera_pan :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    if (input.mouse.buttons_released & MOUSE_BUTTON_RIGHT) != 0 {
        state.camera_pan_active = false;
    }

    if (input.mouse.buttons_pressed & MOUSE_BUTTON_RIGHT) != 0 {
        state.camera_pan_active = camera_ground_point_under_cursor(
            state.camera,
            input.mouse.position_pixels,
            input.framebuffer_size_pixels,
            *state.camera_pan_ground_point
        );
    }

    if !state.camera_pan_active || (input.mouse.buttons_down & MOUSE_BUTTON_RIGHT) == 0 {
        return;
    }

    current_ground_point: V3f;
    if !camera_ground_point_under_cursor(
        state.camera,
        input.mouse.position_pixels,
        input.framebuffer_size_pixels,
        *current_ground_point
    ) {
        state.camera_pan_active = false;
        return;
    }

    movement := state.camera_pan_ground_point - current_ground_point;
    if movement == V3f.{} {
        return;
    }

    state.camera.position += movement;
    state.camera.target += movement;
}

Game_State :: struct {
    tick_count: u64;
    deterministic_seed: u64;
    quit_requested: bool;
    camera: Camera;
    camera_pan_active: bool;
    camera_pan_ground_point: V3f;
    water_molecules: [WATER_MOLECULE_COUNT] Water_Molecule;
    renderer: Renderer;
    store: Store;
    gui: GUI_State;
    gui_demo_open: bool;
    gui_demo_checkbox: bool;
    gui_demo_slider: float32;
    cavity: Cavity_Settings;
    capture_frame_index: u64;
    capture_rgba: [..] u8;
    capture_pixels: [..] Qoi_Pixel;
    capture_qoi: [..] u8;
}

game_start :: (state: *Game_State, platform: *Platform, seed: u64, width: u32, height: u32) {
    state.* = .{};
    state.deterministic_seed = seed;
    state.gui_demo_slider = 0.65;
    state.cavity.strength = 0.65;
    state.cavity.normal_threshold = 0.02;
    state.cavity.width = 0.08;
    state.cavity.fade_start = 20.0;
    state.cavity.fade_end = 90.0;
    state.cavity.minimum_projected_width = 1.25;
    camera_init(*state.camera);
    for 0..WATER_MOLECULE_COUNT - 1 {
        state.water_molecules[it].lane = cast(s32) (it % GRID_ROWS);
        state.water_molecules[it].start_offset = cast(float32) (it / GRID_ROWS) * 9.0;
    }
    log(platform, "Store initialization started");
    store_init(*state.store, platform);
    log(platform, "Store struct initialized");
    store_load_platform_blob(*state.store, platform);
    log(platform, "Store blob loaded");
    store_start_shader_watch(*state.store, platform);
    log(platform, "Store initialization finished");
    gui_init(*state.gui);
    log(platform, "Renderer initialization started");
    renderer_init(*state.renderer, platform, width, height, *state.store);
    log(platform, "Renderer initialization finished");
    if !store_upload_gpu_assets(*state.store, *state.renderer, platform) {
        log(platform, "GPU asset upload failed");
        return;
    }
    log(platform, "GPU asset upload finished");
}

game_reload :: (state: *Game_State, platform: *Platform, seed: u64, width: u32, height: u32) {
    // All persistent state was allocated while the DLL ran under a remapped launcher Context.
    // Its arrays and Pool therefore retain launcher-owned allocator procedures across reloads.
    // Keep the Store, renderer, capture arrays, and GPU handles intact.
}

game_unload :: (state: *Game_State, platform: *Platform) {
    // Reload is not shutdown. The launcher owns state memory and all persistent GPU objects.
    // This hook exists for future rebinding of persistent function pointers, if we add any.
}

game_grid_position :: (column: s32, row: s32) -> V3f {
    x := (cast(float32) column - cast(float32) (GRID_COLUMNS - 1) * 0.5) * GRID_SPACING;
    y := (cast(float32) row - cast(float32) (GRID_ROWS - 1) * 0.5) * GRID_SPACING;
    return .{ x, y, 0 };
}

// No wall clock, file system, socket, or random service reaches the simulation.
// All external facts are supplied by Frame_Input, so recording those inputs is enough to replay.
game_tick :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    state.tick_count += 1;
    store_update_shader_hot_reload(*state.store, platform);
    renderer_reload_changed_shaders(*state.renderer, platform, *state.store);
    if input.wants_quit {
        state.quit_requested = true;
        if platform.system.request_quit {
            platform.system.request_quit();
        }
    }
    gui_begin_frame(*state.gui, input, *state.store.verdana_font);
    if input.keyboard.pressed[KEY_TOGGLE_GUI_DEMO] {
        state.gui_demo_open = !state.gui_demo_open;
    }
    camera_move(*state.camera, input);
    if !state.gui.mouse_captured {
        camera_zoom(*state.camera, input.mouse.wheel_steps, platform);
        camera_pan(state, input, platform);
    }
    renderer_render_game(state, input, platform);
    if input.capture_frame {
        game_capture_frame(state, platform);
    }
}

#load "Store_Renderer.jai";
#load "Renderer_Game.jai";
