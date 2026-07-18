#import "Basic";
#import "Pool";
#import "platform";
#import "game";
#load "webgpu_wasm.jai";

wasm_platform: Platform;
wasm_game: Game_State;
wasm_input: Frame_Input;
wasm_initialized := false;

Wasm_Frame_Input_Bridge_Descriptor :: struct {
    input: *Frame_Input;
    input_bytes: u64;
    simulation_delta_seconds_offset: u64;
    window_size_pixels_offset: u64;
    framebuffer_size_pixels_offset: u64;
    keyboard_down_offset: u64;
    keyboard_pressed_offset: u64;
    keyboard_released_offset: u64;
    movement_key_count: u64;
}

member_offset :: ($T: Type, member_name: string) -> u64 {
    info := type_info(T);
    for info.members {
        if it.name == member_name {
            return cast(u64) it.offset_in_bytes;
        }
    }
    return 0;
}

wasm_install_frame_input_bridge :: () {
    jsInstallFrameInputBuffer :: (params: *void, returns: *void) #foreign;
    descriptor: Wasm_Frame_Input_Bridge_Descriptor = .{};
    descriptor.input = *wasm_input;
    descriptor.input_bytes = size_of(Frame_Input);
    descriptor.simulation_delta_seconds_offset = member_offset(Frame_Input, "simulation_delta_seconds");
    descriptor.window_size_pixels_offset = member_offset(Frame_Input, "window_size_pixels");
    descriptor.framebuffer_size_pixels_offset = member_offset(Frame_Input, "framebuffer_size_pixels");
    descriptor.keyboard_down_offset = member_offset(Frame_Input, "keyboard") + member_offset(Keyboard_State, "down");
    descriptor.keyboard_pressed_offset = member_offset(Frame_Input, "keyboard") + member_offset(Keyboard_State, "pressed");
    descriptor.keyboard_released_offset = member_offset(Frame_Input, "keyboard") + member_offset(Keyboard_State, "released");
    descriptor.movement_key_count = 4;
    jsInstallFrameInputBuffer(*descriptor, null);
}

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

#program_export context_alloc :: (ctx: *#Context, size: s64) -> *void #c_call {
    push_context, defer_pop ctx.*;
    return alloc(size);
}

#program_export context_free :: (ctx: *#Context, memory: *void) #c_call {
    push_context, defer_pop ctx.*;
    free(memory);
}

#program_export "wasm_init" wasm_init :: () #c_call {
    push_context, defer_pop;
    install_wasm_webgpu(*wasm_platform.gpu);
    wasm_platform.system.try_get_asset_blob = wasm_try_get_asset_blob;
    wasm_platform.system.persistent_pool_allocator_proc = pool_allocator_proc;
    wasm_install_frame_input_bridge();
    game_start(*wasm_game, *wasm_platform, 0x4d6f6c6563756c65, 1280, 720);
    wasm_initialized = true;
}

#program_export "wasm_frame" wasm_frame :: () #c_call {
    push_context, defer_pop;
    if !wasm_initialized wasm_init();
    game_tick(*wasm_game, *wasm_input, *wasm_platform);
}
