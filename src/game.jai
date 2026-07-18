#import "Basic";
#import "platform";
#import "Algebra";
#import "Qoi";
#import "renderer";
#import "Store";

GRID_COLUMNS :: 40;
GRID_ROWS :: 15;
GRID_SPACING :: 2.2;
WATER_MOLECULE_COUNT :: 100;
WATER_HEIGHT :: 2.1;
WATER_SPEED :: 8.0;

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
}

camera_init :: (camera: *Camera) {
    camera.position = .{ 0.0, 62.0, 52.0 };
    camera.target = .{ 0, 0, 0 };
    camera.up = .{ 0, 1, 0 };
    camera.focal_length = 1.7320508;
    camera.near_plane = 0.1;
    camera.far_plane = 200.0;
    camera.move_speed = 3.0;
}

camera_view_projection :: (camera: Camera, aspect_ratio: float32) -> M4f {
    view := m4_look_at(camera.position, camera.target, camera.up);
    projection := m4_perspective(camera.focal_length, aspect_ratio, camera.near_plane, camera.far_plane);
    return projection * view;
}

camera_move :: (camera: *Camera, input: *Frame_Input) {
    forward := camera.target - camera.position;
    forward.y = 0;
    forward = normalize(forward);
    right := normalize(cross(forward, .{ 0, 1, 0 }));
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

Game_State :: struct {
    tick_count: u64;
    deterministic_seed: u64;
    quit_requested: bool;
    camera: Camera;
    water_molecules: [WATER_MOLECULE_COUNT] Water_Molecule;
    renderer: Renderer;
    store: Store;
    capture_frame_index: u64;
    capture_rgba: [..] u8;
    capture_pixels: [..] Qoi_Pixel;
    capture_qoi: [..] u8;
}

game_init :: (state: *Game_State, platform: *Platform, seed: u64, width: u32, height: u32) {
    state.* = .{};
    state.deterministic_seed = seed;
    camera_init(*state.camera);
    for 0..WATER_MOLECULE_COUNT - 1 {
        state.water_molecules[it].lane = cast(s32) (it % GRID_ROWS);
        state.water_molecules[it].start_offset = cast(float32) (it / GRID_ROWS) * 9.0;
    }
    store_init(*state.store);
    store_load_platform_blob(*state.store, platform);
    renderer_init(*state.renderer, platform, width, height, *state.store.geometry_shader);
    store_upload_gpu_assets(*state.store, *state.renderer, platform);
}

game_grid_position :: (column: s32, row: s32) -> V3f {
    x := (cast(float32) column - cast(float32) (GRID_COLUMNS - 1) * 0.5) * GRID_SPACING;
    z := (cast(float32) row - cast(float32) (GRID_ROWS - 1) * 0.5) * GRID_SPACING;
    return .{ x, 0, z };
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
    camera_move(*state.camera, input);
    renderer_render_game(state, input, platform);
    if input.capture_frame {
        game_capture_frame(state, platform);
    }
}

#load "Store_Renderer.jai";
#load "Renderer_Game.jai";
