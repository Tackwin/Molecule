#import "Basic";
#import "Pool";
#import "platform";
#import "game";
#load "webgpu_wasm.jai";

wasm_platform: Platform;
wasm_game: Game_State;
wasm_input: Frame_Input;
wasm_initialized := false;
WASM_MAX_WATCH_CHANGES :: 64;
WASM_WATCH_PATH_BYTES :: 0x4000;
wasm_watch_changes: [WASM_MAX_WATCH_CHANGES] Watched_File_Change;
wasm_watch_path_bytes: [WASM_WATCH_PATH_BYTES] u8;

Wasm_Byte_Slice_Params :: struct {
    data: *u8;
    count: u64;
}

wasm_log :: (text: [] u8) {
    jsLog :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        data: *u8;
        count: u64;
    }
    params: Params = .{ data = text.data, count = xx text.count };
    jsLog(*params, null);
}

wasm_pool_allocator_proc :: (
    mode: Allocator_Mode,
    size: s64,
    old_size: s64,
    old_memory: *void,
    allocator_data: *void
) -> *void {
    return pool_allocator_proc(mode, size, old_size, old_memory, allocator_data);
}

Wasm_Frame_Input_Bridge_Descriptor :: struct {
    input: *Frame_Input;
    input_bytes: u64;
    simulation_delta_seconds_offset: u64;
    window_size_pixels_offset: u64;
    framebuffer_size_pixels_offset: u64;
    keyboard_down_offset: u64;
    keyboard_pressed_offset: u64;
    keyboard_released_offset: u64;
    mouse_position_offset: u64;
    mouse_delta_offset: u64;
    mouse_wheel_offset: u64;
    mouse_buttons_down_offset: u64;
    mouse_buttons_pressed_offset: u64;
    mouse_buttons_released_offset: u64;
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
    descriptor.mouse_position_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "position_pixels");
    descriptor.mouse_delta_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "delta_pixels");
    descriptor.mouse_wheel_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "wheel_steps");
    descriptor.mouse_buttons_down_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "buttons_down");
    descriptor.mouse_buttons_pressed_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "buttons_pressed");
    descriptor.mouse_buttons_released_offset = member_offset(Frame_Input, "mouse") + member_offset(Mouse_State, "buttons_released");
    descriptor.movement_key_count = KEY_TOGGLE_GUI_DEMO + 1;
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
    fetch_started := "WASM asset blob fetch started";
    wasm_log(.{ data = fetch_started.data, count = fetch_started.count });
    byte_count := wasm_fetch_asset_blob_byte_count();
    if byte_count == 0 {
        return .{};
    }

    byte_count_message := tprint("WASM asset blob bytes: %", byte_count);
    wasm_log(.{ data = byte_count_message.data, count = byte_count_message.count });

    blob: [] u8;
    blob.count = cast(int) byte_count;
    blob.data = alloc(blob.count);
    if !blob.data {
        return .{};
    }

    wasm_copy_fetched_asset_blob(blob.data, byte_count);
    fetch_finished := "WASM asset blob copied";
    wasm_log(.{ data = fetch_finished.data, count = fetch_finished.count });
    return blob;
}

wasm_asset_request_async :: (path: [] u8) -> Asset_Request_Handle {
    jsAssetRequestAsync :: (params: *void, returns: *void) #foreign;
    params: Wasm_Byte_Slice_Params = .{
        data = path.data,
        count = cast(u64) path.count,
    };
    result: Asset_Request_Handle;
    jsAssetRequestAsync(*params, *result);
    return result;
}

wasm_asset_get_status :: (handle: Asset_Request_Handle) -> Asset_Request_Status {
    jsAssetGetStatus :: (params: *void, returns: *void) #foreign;
    result: Asset_Request_Status;
    jsAssetGetStatus(*handle, *result);
    return result;
}

wasm_asset_take :: (handle: Asset_Request_Handle, allocator: Allocator) -> [] u8 {
    jsAssetTakeByteCount :: (params: *void, returns: *void) #foreign;
    jsAssetTakeCopyAndClose :: (params: *void, returns: *void) #foreign;
    byte_count: u64;
    jsAssetTakeByteCount(*handle, *byte_count);
    if byte_count == 0 return .{};

    result: [] u8;
    result.count = cast(int) byte_count;
    ctx: #Context;
    push_context ctx {
        context.allocator = allocator;
        result.data = alloc(result.count);
    }
    if !result.data return .{};

    Params :: struct {
        handle: Asset_Request_Handle;
        padding: u32;
        destination: *u8;
        byte_count: u64;
    }
    params: Params = .{
        handle = handle,
        destination = result.data,
        byte_count = byte_count,
    };
    jsAssetTakeCopyAndClose(*params, null);
    return result;
}

wasm_watch_file_changes :: (directory: [] u8) -> File_Watch_Handle {
    jsWatchFileChanges :: (params: *void, returns: *void) #foreign;
    params: Wasm_Byte_Slice_Params = .{
        data = directory.data,
        count = cast(u64) directory.count,
    };
    result: File_Watch_Handle;
    jsWatchFileChanges(*params, *result);
    return result;
}

wasm_pull_watch_changes :: (handle: File_Watch_Handle) -> [] Watched_File_Change {
    jsPullWatchChanges :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        handle: File_Watch_Handle;
        padding: u32;
        path_bytes: *u8;
        path_capacity: u64;
    }
    params: Params = .{
        handle = handle,
        path_bytes = *wasm_watch_path_bytes[0],
        path_capacity = WASM_WATCH_PATH_BYTES,
    };
    path_bytes_used: u64;
    jsPullWatchChanges(*params, *path_bytes_used);
    change_count: s64;
    path_start: u64;
    if path_bytes_used > 0 {
        for byte_index: 0..path_bytes_used - 1 {
            if wasm_watch_path_bytes[byte_index] != #char "\n" continue;
            if change_count >= WASM_MAX_WATCH_CHANGES break;
            wasm_watch_changes[change_count].path = .{
                data = *wasm_watch_path_bytes[path_start],
                count = cast(int) (byte_index - path_start),
            };
            wasm_watch_changes[change_count].kind = .MODIFIED;
            change_count += 1;
            path_start = byte_index + 1;
        }
    }
    return .{
        data = *wasm_watch_changes[0],
        count = cast(int) change_count,
    };
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
    wasm_platform.system.log = wasm_log;
    wasm_platform.system.try_get_asset_blob = wasm_try_get_asset_blob;
    wasm_platform.system.asset_request_async = wasm_asset_request_async;
    wasm_platform.system.asset_get_status = wasm_asset_get_status;
    wasm_platform.system.asset_take = wasm_asset_take;
    wasm_platform.system.watch_file_changes = wasm_watch_file_changes;
    wasm_platform.system.pull_watch_changes = wasm_pull_watch_changes;
    wasm_platform.system.persistent_pool_allocator_proc = wasm_pool_allocator_proc;
    wasm_install_frame_input_bridge();
    init_started := "WASM game initialization started";
    wasm_log(.{ data = init_started.data, count = init_started.count });
    game_start(*wasm_game, *wasm_platform, 0x4d6f6c6563756c65, 1280, 720);
    init_finished := "WASM game initialization finished";
    wasm_log(.{ data = init_finished.data, count = init_finished.count });
    wasm_initialized = true;
}

#program_export "wasm_frame" wasm_frame :: () #c_call {
    push_context, defer_pop;
    if !wasm_initialized wasm_init();
    game_tick(*wasm_game, *wasm_input, *wasm_platform);
}
