#import "Basic";
#import "platform";
#import "game";
#load "webgpu_wasm.jai";

wasm_platform: Platform;
wasm_game: Game_State;
wasm_input: Frame_Input;
wasm_initialized := false;

wasm_fetch_asset_blob_byte_count :: () -> u64 #c_call {
    jsFetchAssetBlob :: (params: *void, returns: *void) #foreign;
    byte_count: u64;
    jsFetchAssetBlob(null, *byte_count);
    return byte_count;
}

wasm_copy_fetched_asset_blob :: (destination: *u8, byte_count: u64) #c_call {
    jsCopyFetchedAssetBlob :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        destination: *u8;
        byte_count: u64;
    }
    params: Params;
    params.destination = destination;
    params.byte_count = byte_count;
    jsCopyFetchedAssetBlob(*params, null);
}

wasm_try_get_asset_blob :: () -> [] u8 {
    byte_count := wasm_fetch_asset_blob_byte_count();
    if byte_count == 0 {
        return .{};
    }

    blob: [] u8;
    blob.count = cast(int) byte_count;
    blob.data = alloc(blob.count);
    if !blob.data {
        return .{};
    }

    wasm_copy_fetched_asset_blob(blob.data, byte_count);
    return blob;
}

#program_export "wasm_init" wasm_init :: () #c_call {
    push_context, defer_pop;
    install_wasm_webgpu(*wasm_platform.gpu);
    wasm_platform.system.try_get_asset_blob = wasm_try_get_asset_blob;
    game_init(*wasm_game, *wasm_platform, 0x4d6f6c6563756c65, 1280, 720);
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

// The browser maps physical keys to these four game actions.  Keeping browser
// key codes out of Frame_Input makes recorded input portable across hosts.
#program_export "wasm_set_move_key" wasm_set_move_key :: (
    key: u32,
    down: u8,
    pressed: u8,
    released: u8
) #c_call {
    if key >= 4 {
        return;
    }
    wasm_input.keyboard.down[key] = down != 0;
    wasm_input.keyboard.pressed[key] = pressed != 0;
    wasm_input.keyboard.released[key] = released != 0;
}

#program_export "wasm_frame" wasm_frame :: () #c_call {
    push_context, defer_pop;
    if !wasm_initialized wasm_init();
    game_tick(*wasm_game, *wasm_input, *wasm_platform);
}
