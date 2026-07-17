#import "Basic";
#import "platform";
#import "Algebra";
#import "renderer";
#import "Store";

Game_State :: struct {
    tick_count: u64;
    deterministic_seed: u64;
    quit_requested: bool;
    triangle_offset: V2f;
    renderer: Renderer;
    store: Store;
}

game_init :: (state: *Game_State, platform: *Platform, seed: u64, width: u32, height: u32) {
    state.* = .{};
    state.deterministic_seed = seed;
    store_init(*state.store);
    store_load_platform_blob(*state.store, platform);
    renderer_init(*state.renderer, platform, width, height, state.store.triangle_shader.asset.bytes);
}

// No wall clock, file system, socket, or random service reaches the simulation.
// All external facts are supplied by Frame_Input, so recording those inputs is enough to replay.
game_tick :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    state.tick_count += 1;
    if input.wants_quit {
        state.quit_requested = true;
        if platform.system.request_quit platform.system.request_quit();
    }

    move: V2f = .{};
    if input.keyboard.down[KEY_MOVE_UP] {
        move.y += 1;
    }
    if input.keyboard.down[KEY_MOVE_LEFT] {
        move.x -= 1;
    }
    if input.keyboard.down[KEY_MOVE_DOWN] {
        move.y -= 1;
    }
    if input.keyboard.down[KEY_MOVE_RIGHT] {
        move.x += 1;
    }
    state.triangle_offset += move * (0.75 * input.simulation_delta_seconds);
    renderer_draw(*state.renderer, platform, state.triangle_offset);
}
