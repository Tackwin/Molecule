#import "Basic";
#import "platform";
#import "Remap_Context"(false);
#import "game";

#program_export "game_start"
game_dll_start :: (
    platform: *Platform, seed: u64, width: u32, height: u32
) -> *void {
    Remap_Context();
    state := New(Game_State);
    game_start(state, platform, seed, width, height);
    return state;
}

#program_export "game_reload"
game_dll_reload :: (
    state: *void, platform: *Platform, seed: u64, width: u32, height: u32
) {
    Remap_Context();
    game_reload(cast(*Game_State, state), platform, seed, width, height);
}

#program_export "game_tick"
game_dll_tick :: (
    state: *void, input: *Frame_Input, platform: *Platform
) {
    Remap_Context();
    game_tick(cast(*Game_State, state), input, platform);
}

#program_export "game_unload"
game_dll_unload :: (state: *void, platform: *Platform) {
    Remap_Context();
    game_unload(cast(*Game_State, state), platform);
}
