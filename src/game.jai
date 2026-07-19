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
WATER_SPEED :: 1.0;

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

camera_view_projection :: (camera: Camera, aspect_ratio: float32) -> M4f {
    view := m4_look_at(camera.position, camera.target, camera.up);
    projection := m4_perspective(camera.focal_length, aspect_ratio, camera.near_plane, camera.far_plane);
    return projection * view;
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

camera_zoom :: (camera: *Camera, wheel_steps: s32) {
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

Game_State :: struct {
    tick_count: u64;
    deterministic_seed: u64;
    quit_requested: bool;
    camera: Camera;
    water_molecules: [WATER_MOLECULE_COUNT] Water_Molecule;
    renderer: Renderer;
    store: Store;
    gui: GUI_State;
    gui_demo_open: bool;
    gui_demo_checkbox: bool;
    gui_demo_slider: float32;
    capture_frame_index: u64;
    capture_rgba: [..] u8;
    capture_pixels: [..] Qoi_Pixel;
    capture_qoi: [..] u8;
}

game_start :: (state: *Game_State, platform: *Platform, seed: u64, width: u32, height: u32) {
    state.* = .{};
    state.deterministic_seed = seed;
    state.gui_demo_slider = 0.65;
    camera_init(*state.camera);
    for 0..WATER_MOLECULE_COUNT - 1 {
        state.water_molecules[it].lane = cast(s32) (it % GRID_ROWS);
        state.water_molecules[it].start_offset = cast(float32) (it / GRID_ROWS) * 9.0;
    }
    store_init(*state.store, platform);
    store_load_platform_blob(*state.store, platform);
    gui_init(*state.gui);
    renderer_init(*state.renderer, platform, width, height, *state.store);
    store_upload_gpu_assets(*state.store, *state.renderer, platform);
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
        camera_zoom(*state.camera, input.mouse.wheel_steps);
    }
    renderer_render_game(state, input, platform);
    if input.capture_frame {
        game_capture_frame(state, platform);
    }
}

#load "Store_Renderer.jai";
#load "Renderer_Game.jai";
