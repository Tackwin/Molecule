#import "Basic";
#import "platform";
#import "game";
#import "renderer";
#load "webgpu_wasm.jai";

wasm_platform: Platform;
wasm_game: Game_State;
wasm_input: Frame_Input;
wasm_renderer: Renderer;
wasm_initialized := false;

#program_export "wasm_init" wasm_init :: () #c_call {
    push_context, defer_pop;
    install_wasm_webgpu(*wasm_platform.gpu);
    game_init(*wasm_game, 0x4d6f6c6563756c65);
    renderer_init(*wasm_renderer, *wasm_platform, 1280, 720);
    wasm_initialized = true;
}

// This is a narrow ABI boundary, so the JavaScript host never depends on Jai struct padding.
#program_export "wasm_set_frame_basics" wasm_set_frame_basics :: (
    delta_seconds: float32,
    window_width: s32, window_height: s32,
    framebuffer_width: s32, framebuffer_height: s32
) #c_call {
    wasm_input = .{};
    wasm_input.simulation_delta_seconds = delta_seconds;
    wasm_input.window_size_pixels = .{ window_width, window_height };
    wasm_input.framebuffer_size_pixels = .{ framebuffer_width, framebuffer_height };
}

#program_export "wasm_frame" wasm_frame :: () #c_call {
    push_context, defer_pop;
    if !wasm_initialized wasm_init();
    game_tick(*wasm_game, *wasm_input, *wasm_platform);
    renderer_draw(*wasm_renderer, *wasm_platform);
}
