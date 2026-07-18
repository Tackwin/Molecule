#import "Basic";
#import "SDL";
#import "File";
#import "File_Watcher";
#import "Pool";
#import "String";
#import "Windows";
#import "platform";
#load "../Win32_Control.jai";
#load "webgpu_win32.jai";

platform_quit_requested := false;
win32_asset_blob: [] u8;
win32_sdl_movement_down: [4] bool;

CreateDirectoryA :: (path: *u8, security_attributes: *void) -> BOOL #foreign kernel32;

win32_try_get_asset_blob :: () -> [] u8 {
    return win32_asset_blob;
}

win32_pool_allocator_proc :: (
    mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void
) -> *void {
    return pool_allocator_proc(mode, size, old_size, old_memory, allocator_data);
}

Win32_Asset_Request :: struct {
    data: string;
    status: Asset_Request_Status;
}

win32_asset_requests: [64] Win32_Asset_Request;

win32_asset_request_async :: (path: [] u8) -> Asset_Request_Handle {
    for 1..win32_asset_requests.count - 1 {
        request := *win32_asset_requests[it];
        if request.status.state == .EMPTY {
            path_string: string = .{ data = path.data, count = path.count };
            data, loaded := read_entire_file(tprint("Assets/%", path_string), log_errors = false);
            request.data = data;
            if loaded {
                request.status.state = .READY;
                request.status.bytes_received = xx request.data.count;
                request.status.bytes_total = xx request.data.count;
            } else {
                request.status.state = .FAILED;
                request.status.error_code = 2;
            }
            return xx it;
        }
    }
    return 0;
}

win32_asset_get_status :: (handle: Asset_Request_Handle) -> Asset_Request_Status {
    if handle == 0 || handle >= win32_asset_requests.count return .{ state = .FAILED, error_code = 1 };
    return win32_asset_requests[handle].status;
}

win32_asset_take :: (handle: Asset_Request_Handle, allocator: Allocator) -> [] u8 {
    if handle == 0 || handle >= win32_asset_requests.count return .{};
    request := *win32_asset_requests[handle];
    if request.status.state != .READY return .{};
    result: [] u8;
    result.count = request.data.count;
    ctx: #Context;
    push_context ctx {
        context.allocator = allocator;
        result.data = alloc(result.count);
    }
    memcpy(result.data, request.data.data, result.count);
    free(request.data.data);
    request.* = .{};
    return result;
}

Win32_Asset_Blob :: struct {
    file: File;
    mapping: HANDLE;
    data: [] u8;
}

win32_map_asset_blob :: () -> Win32_Asset_Blob, bool {
    blob_file, file_loaded := file_open("assets.blob", log_errors = true);
    if !file_loaded {
        return .{}, false;
    }
    size: LARGE_INTEGER;
    if !GetFileSizeEx(blob_file.handle, *size) {
        file_close(*blob_file);
        return .{}, false;
    }
    mapping := CreateFileMappingW(blob_file.handle, null, PAGE_READONLY, 0, 0, null);
    if !mapping {
        file_close(*blob_file);
        return .{}, false;
    }
    memory := MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, xx size.QuadPart);
    if !memory {
        CloseHandle(mapping);
        file_close(*blob_file);
        return .{}, false;
    }
    return .{ file = blob_file, mapping = mapping, data = .{ data = xx memory, count = size.QuadPart } }, true;
}

win32_request_quit :: () { platform_quit_requested = true; }

win32_write_file :: (path: [] u8, data: [] u8) -> bool {
    CreateDirectoryA("captures".data, null);
    path_string: string = .{ data = path.data, count = path.count };
    output, opened := file_open(path_string, for_writing = true, keep_existing_content = false);
    if !opened {
        return false;
    }
    defer file_close(*output);
    return file_write(*output, data.data, data.count);
}

win32_capture_rgba :: (width: u32, height: u32, rgba: [] u8) -> bool {
    if rgba.count != xx (cast(u64) width * height * 4) {
        return false;
    }
    info: SDL_SysWMinfo = .{};
    SDL_VERSION(*info.version);
    if !SDL_GetWindowWMInfo(win32_webgpu_window, *info) {
        return false;
    }
    hwnd := xx info.info.win.window;
    source_dc := GetDC(hwnd);
    if !source_dc {
        return false;
    }
    defer ReleaseDC(hwnd, source_dc);
    memory_dc := CreateCompatibleDC(source_dc);
    if !memory_dc {
        return false;
    }
    defer DeleteDC(memory_dc);
    bitmap := CreateCompatibleBitmap(source_dc, cast(s32) width, cast(s32) height);
    if !bitmap {
        return false;
    }
    defer DeleteObject(xx bitmap);
    previous_bitmap := SelectObject(memory_dc, xx bitmap);
    defer SelectObject(memory_dc, previous_bitmap);
    if !BitBlt(memory_dc, 0, 0, cast(s32) width, cast(s32) height, source_dc, 0, 0, .SRCCOPY) {
        return false;
    }
    bitmap_info: BITMAPINFO = .{};
    bitmap_info.bmiHeader.biSize = size_of(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = cast(s32) width;
    bitmap_info.bmiHeader.biHeight = -cast(s32) height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;
    if GetDIBits(memory_dc, bitmap, 0, height, rgba.data, *bitmap_info, DIB_RGB_COLORS) != cast(s32) height {
        return false;
    }
    for 0..width * height - 1 {
        byte_index := it * 4;
        blue := rgba[byte_index + 0];
        rgba[byte_index + 0] = rgba[byte_index + 2];
        rgba[byte_index + 2] = blue;
        rgba[byte_index + 3] = 255;
    }
    return true;
}

win32_set_movement_key :: (input: *Frame_Input, key: SDL_Keycode, is_down: bool, is_pressed: bool, is_released: bool) {
    index: s32 = -1;
    if key == SDLK_z || key == SDLK_UP {
        index = KEY_MOVE_UP;
    }
    if key == SDLK_q || key == SDLK_LEFT {
        index = KEY_MOVE_LEFT;
    }
    if key == SDLK_s || key == SDLK_DOWN {
        index = KEY_MOVE_DOWN;
    }
    if key == SDLK_d || key == SDLK_RIGHT {
        index = KEY_MOVE_RIGHT;
    }
    if index < 0 {
        return;
    }
    win32_sdl_movement_down[index] = is_down;
    input.keyboard.down[index] = is_down;
    input.keyboard.pressed[index] = is_pressed;
    input.keyboard.released[index] = is_released;
}

make_win32_platform :: () -> Platform {
    platform: Platform;
    platform.system.request_quit = win32_request_quit;
    platform.system.write_file = win32_write_file;
    platform.system.capture_rgba = win32_capture_rgba;
    platform.system.try_get_asset_blob = win32_try_get_asset_blob;
    platform.system.asset_request_async = win32_asset_request_async;
    platform.system.asset_get_status = win32_asset_get_status;
    platform.system.asset_take = win32_asset_take;
    platform.system.persistent_pool_allocator_proc = win32_pool_allocator_proc;
    return platform;
}

poll_win32_input :: (window: *SDL_Window, input: *Frame_Input) {
    // Reset transient edge state; down state survives from the preceding frame.
    for 0..MAX_KEYS-1 {
        input.keyboard.pressed[it] = false;
        input.keyboard.released[it] = false;
    }
    for 0..3 {
        input.keyboard.down[it] = win32_sdl_movement_down[it];
    }
    input.mouse.delta_pixels = .{};
    input.mouse.wheel_steps = 0;
    input.mouse.buttons_pressed = 0;
    input.mouse.buttons_released = 0;
    input.wants_quit = false;
    input.capture_frame = false;
    input.simulation_delta_seconds = 1.0 / 60.0;

    event: SDL_Event;
    while SDL_PollEvent(*event) {
        if event.type == {
            case SDL_QUIT;
                input.wants_quit = true;
            case SDL_KEYDOWN;
                key := event.key.keysym.sym;
                if key >= 0 && key < MAX_KEYS {
                    input.keyboard.down[key] = true;
                    input.keyboard.pressed[key] = true;
                }
                win32_set_movement_key(input, key, true, true, false);
                if key == SDLK_ESCAPE input.wants_quit = true;
            case SDL_KEYUP;
                key := event.key.keysym.sym;
                if key >= 0 && key < MAX_KEYS {
                    input.keyboard.down[key] = false;
                    input.keyboard.released[key] = true;
                }
                win32_set_movement_key(input, key, false, false, true);
            case SDL_MOUSEMOTION;
                input.mouse.position_pixels = .{ event.motion.x, event.motion.y };
                input.mouse.delta_pixels = .{ event.motion.xrel, event.motion.yrel };
            case SDL_MOUSEWHEEL;
                input.mouse.wheel_steps = event.wheel.y;
        }
    }

    SDL_GetWindowSize(window, *input.window_size_pixels.x, *input.window_size_pixels.y);
    input.framebuffer_size_pixels = input.window_size_pixels;
}

Win32_Game_Dll :: struct {
    module: HMODULE;
    api: Game_Dll_Api;
}

Win32_Reload_Notification :: struct {
    requested: bool;
}

Win32_Reload_Watcher :: File_Watcher(Win32_Reload_Notification);

win32_game_dll_file_changed :: (
    watcher: *Win32_Reload_Watcher,
    change: *File_Change,
    notification: *Win32_Reload_Notification
) {
    if ends_with(change.full_path, "MoleculeGame.dll") {
        notification.requested = true;
    }
}

win32_get_game_dll_proc :: ($T: Type, module: HMODULE, name: string) -> T {
    return cast(T, GetProcAddress(module, name.data));
}

win32_load_game_dll :: (dll: *Win32_Game_Dll, generation: u64) -> bool {
    CreateDirectoryA("hot".data, null);
    temporary_dll_path := tprint("hot/MoleculeGame_%.dll", generation);
    if !CopyFileA("MoleculeGame.dll".data, temporary_dll_path.data, 0) {
        return false;
    }
    temporary_pdb_path := tprint("hot/MoleculeGame_%.pdb", generation);
    CopyFileA("MoleculeGame.pdb".data, temporary_pdb_path.data, 0);

    module := LoadLibraryA(temporary_dll_path.data);
    if !module {
        return false;
    }
    candidate: Win32_Game_Dll = .{};
    candidate.module = module;
    candidate.api.start = win32_get_game_dll_proc(Game_Start_Proc, module, "game_start");
    candidate.api.reload = win32_get_game_dll_proc(Game_Reload_Proc, module, "game_reload");
    candidate.api.tick = win32_get_game_dll_proc(Game_Tick_Proc, module, "game_tick");
    candidate.api.unload = win32_get_game_dll_proc(Game_Unload_Proc, module, "game_unload");
    if !candidate.api.start || !candidate.api.reload || !candidate.api.tick || !candidate.api.unload {
        FreeLibrary(module);
        return false;
    }
    dll.* = candidate;
    return true;
}

win32_unload_game_dll :: (dll: *Win32_Game_Dll, state: *void, platform: *Platform) {
    if !dll.module {
        return;
    }
    if state {
        dll.api.unload(state, platform);
    }
    FreeLibrary(dll.module);
    dll.* = .{};
}

win32_reload_game_dll :: (
    active_dll: *Win32_Game_Dll,
    state: **void,
    platform: *Platform,
    seed: u64,
    width: u32,
    height: u32,
    generation: u64
) -> bool {
    candidate: Win32_Game_Dll;
    if !win32_load_game_dll(*candidate, generation) {
        return false;
    }
    if state.* {
        win32_unload_game_dll(active_dll, state.*, platform);
        candidate.api.reload(state.*, platform, seed, width, height);
    } else {
        state.* = candidate.api.start(platform, seed, width, height);
        if !state.* {
            FreeLibrary(candidate.module);
            return false;
        }
    }
    active_dll.* = candidate;
    return true;
}

main :: () {
    if SDL_Init(SDL_INIT_VIDEO) != 0 return;
    defer SDL_Quit();

    window := SDL_CreateWindow(
        "Molecule", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        1280, 720, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI
    );
    if window == null return;
    defer SDL_DestroyWindow(window);

    platform := make_win32_platform();
    install_win32_webgpu(*platform.gpu, window);
    asset_blob, asset_blob_loaded := win32_map_asset_blob();
    if !asset_blob_loaded return;
    win32_asset_blob = asset_blob.data;
    defer UnmapViewOfFile(asset_blob.data.data);
    defer CloseHandle(asset_blob.mapping);
    defer file_close(*asset_blob.file);
    input: Frame_Input;
    control: Win32_Control;
    if !win32_control_open(*control) {
        return;
    }
    defer win32_control_shutdown(*control);
    reload_notification: Win32_Reload_Notification;
    reload_watcher: Win32_Reload_Watcher;
    if !init(*reload_watcher, win32_game_dll_file_changed, *reload_notification, events_to_watch = .MODIFIED | .ADDED | .MOVED) {
        return;
    }
    defer deinit(reload_watcher);
    if !add_directories(*reload_watcher, ".") {
        return;
    }
    game_dll: Win32_Game_Dll;
    game_state: *void;
    reload_generation: u64 = 1;
    if !win32_reload_game_dll(*game_dll, *game_state, *platform, 0x4d6f6c6563756c65, 1280, 720, reload_generation) {
        return;
    }
    reload_generation += 1;
    defer win32_unload_game_dll(*game_dll, game_state, *platform);
    while !platform_quit_requested {
        poll_win32_input(window, *input);
        win32_control_poll(*control);
        win32_control_merge_input(*control, *input);
        process_changes(*reload_watcher);
        if reload_notification.requested {
            if win32_reload_game_dll(
                *game_dll,
                *game_state,
                *platform,
                0x4d6f6c6563756c65,
                xx input.framebuffer_size_pixels.x,
                xx input.framebuffer_size_pixels.y,
                reload_generation
            ) {
                reload_notification.requested = false;
                reload_generation += 1;
            }
        }
        if !control.paused {
            game_dll.api.tick(game_state, *input, *platform);
        }
        if input.wants_quit platform_quit_requested = true;
        SDL_Delay(1);
    }
}
