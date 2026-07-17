#import "Basic";
#import "platform";

Game_State :: struct {
    tick_count: u64;
    deterministic_seed: u64;
    quit_requested: bool;
}

game_init :: (state: *Game_State, seed: u64) {
    state.* = .{};
    state.deterministic_seed = seed;
}

// No wall clock, file system, socket, or random service reaches the simulation.
// All external facts are supplied by Frame_Input, so recording those inputs is enough to replay.
game_tick :: (state: *Game_State, input: *Frame_Input, platform: *Platform) {
    state.tick_count += 1;
    if input.wants_quit {
        state.quit_requested = true;
        if platform.system.request_quit platform.system.request_quit();
    }

    // Rendering is intentionally separate from state mutation. A later renderer can use
    // platform.gpu without making gameplay depend on GPU timing or results.
}
