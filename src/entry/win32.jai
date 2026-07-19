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
win32_sdl_movement_down: [KEY_TOGGLE_GUI_DEMO + 1] bool;

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

WIN32_MAX_FILE_WATCHES :: 8;
WIN32_MAX_FILE_WATCH_CHANGES :: 0x40;
WIN32_MAX_WATCHED_PATH_BYTES :: 0x200;

Win32_File_Watcher :: File_Watcher(u32);

Win32_File_Watch :: struct {
    active: bool;
    index: u32;
    watcher: Win32_File_Watcher;
    change_count: u32;
    changes: [WIN32_MAX_FILE_WATCH_CHANGES] Watched_File_Change;
    path_bytes: [WIN32_MAX_FILE_WATCH_CHANGES][WIN32_MAX_WATCHED_PATH_BYTES] u8;
}

win32_file_watches: [WIN32_MAX_FILE_WATCHES] Win32_File_Watch;

win32_file_change_kind :: (events: File_Change_Event) -> Watched_File_Change_Kind {
    result: Watched_File_Change_Kind;
    if events & .ADDED result |= .ADDED;
    if events & .MODIFIED result |= .MODIFIED;
    if events & .MOVED result |= .MOVED;
    if events & .REMOVED result |= .REMOVED;
    return result;
}

win32_watched_file_changed :: (
    watcher: *Win32_File_Watcher,
    change: *File_Change,
    watch_index: *u32
) {
    if watch_index.* >= win32_file_watches.count return;
    slot := *win32_file_watches[watch_index.*];
    normalized_count := min(change.full_path.count, WIN32_MAX_WATCHED_PATH_BYTES);
    if slot.change_count > 0 {
        for 0..slot.change_count - 1 {
            existing := slot.changes[it];
            if existing.path.count != normalized_count continue;
            matches := true;
            if normalized_count > 0 {
                for byte_index: 0..normalized_count - 1 {
                    byte := change.full_path.data[byte_index];
                    if byte == #char "\\" byte = #char "/";
                    if existing.path[byte_index] != byte {
                        matches = false;
                        break;
                    }
                }
            }
            if matches {
                slot.changes[it].kind |= win32_file_change_kind(change.events);
                return;
            }
        }
    }
    if slot.change_count >= WIN32_MAX_FILE_WATCH_CHANGES return;
    change_index := slot.change_count;
    if normalized_count > 0 {
        for byte_index: 0..normalized_count - 1 {
            byte := change.full_path.data[byte_index];
            if byte == #char "\\" byte = #char "/";
            slot.path_bytes[change_index][byte_index] = byte;
        }
    }
    slot.changes[change_index].path = .{
        data = *slot.path_bytes[change_index][0],
        count = normalized_count,
    };
    slot.changes[change_index].kind = win32_file_change_kind(change.events);
    slot.change_count += 1;
}

win32_watch_file_changes :: (directory: [] u8) -> File_Watch_Handle {
    for 0..win32_file_watches.count - 1 {
        slot := *win32_file_watches[it];
        if slot.active continue;
        slot.* = .{};
        slot.index = xx it;
        if !init(
            *slot.watcher,
            win32_watched_file_changed,
            *slot.index,
            events_to_watch = .MODIFIED | .ADDED | .MOVED | .REMOVED
        ) {
            slot.* = .{};
            return 0;
        }
        directory_string: string = .{ data = directory.data, count = directory.count };
        asset_directory := tprint("../Assets/%", directory_string);
        if !add_directories(*slot.watcher, asset_directory) {
            deinit(slot.watcher);
            slot.* = .{};
            return 0;
        }
        slot.active = true;
        return cast(u32) (it + 1);
    }
    return 0;
}

win32_pull_watch_changes :: (handle: File_Watch_Handle) -> [] Watched_File_Change {
    if handle == 0 || handle > win32_file_watches.count return .{};
    slot := *win32_file_watches[handle - 1];
    if !slot.active return .{};
    process_changes(*slot.watcher);
    result: [] Watched_File_Change = .{
        data = *slot.changes[0],
        count = slot.change_count,
    };
    slot.change_count = 0;
    return result;
}

win32_shutdown_file_watches :: () {
    for * slot: win32_file_watches {
        if !slot.active continue;
        deinit(slot.watcher);
        slot.* = .{};
    }
}

win32_asset_request_async :: (path: [] u8) -> Asset_Request_Handle {
    for 1..win32_asset_requests.count - 1 {
        request := *win32_asset_requests[it];
        if request.status.state == .EMPTY {
            path_string: string = .{ data = path.data, count = path.count };
            data, loaded := read_entire_file(tprint("../Assets/%", path_string), log_errors = false);
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

win32_log :: (text: [] u8) {
    message: string = .{ data = text.data, count = text.count };
    print("%\n", message);
}

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
    if key == SDLK_F8 {
        index = KEY_TOGGLE_GUI_DEMO;
    }
    if index < 0 || index >= win32_sdl_movement_down.count {
        return;
    }
    win32_sdl_movement_down[index] = is_down;
    input.keyboard.down[index] = is_down;
    input.keyboard.pressed[index] = is_pressed;
    input.keyboard.released[index] = is_released;
}

make_win32_platform :: () -> Platform {
    platform: Platform;
    platform.system.log = win32_log;
    platform.system.request_quit = win32_request_quit;
    platform.system.write_file = win32_write_file;
    platform.system.try_get_asset_blob = win32_try_get_asset_blob;
    platform.system.asset_request_async = win32_asset_request_async;
    platform.system.asset_get_status = win32_asset_get_status;
    platform.system.asset_take = win32_asset_take;
    platform.system.watch_file_changes = win32_watch_file_changes;
    platform.system.pull_watch_changes = win32_pull_watch_changes;
    platform.system.persistent_pool_allocator_proc = win32_pool_allocator_proc;
    return platform;
}

poll_win32_input :: (window: *SDL_Window, input: *Frame_Input) {
    // Reset transient edge state; down state survives from the preceding frame.
    for 0..MAX_KEYS-1 {
        input.keyboard.pressed[it] = false;
        input.keyboard.released[it] = false;
    }
    for 0..win32_sdl_movement_down.count - 1 {
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
            case SDL_MOUSEBUTTONDOWN;
                if event.button.button == SDL_BUTTON_LEFT {
                    input.mouse.buttons_down |= 1;
                    input.mouse.buttons_pressed |= 1;
                } else if event.button.button == SDL_BUTTON_RIGHT {
                    input.mouse.buttons_down |= 2;
                    input.mouse.buttons_pressed |= 2;
                }
                input.mouse.position_pixels = .{ event.button.x, event.button.y };
            case SDL_MOUSEBUTTONUP;
                if event.button.button == SDL_BUTTON_LEFT {
                    input.mouse.buttons_down &= 0xfe;
                    input.mouse.buttons_released |= 1;
                } else if event.button.button == SDL_BUTTON_RIGHT {
                    input.mouse.buttons_down &= 0xfd;
                    input.mouse.buttons_released |= 2;
                }
                input.mouse.position_pixels = .{ event.button.x, event.button.y };
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
    defer win32_shutdown_file_watches();
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
        if !control.paused || control.step_frames > 0 {
            win32_control_merge_input(*control, *input);
            game_dll.api.tick(game_state, *input, *platform);
            if control.paused && control.step_frames > 0 {
                control.step_frames -= 1;
            }
        }
        if control.quit_requested {
            platform_quit_requested = true;
            control.quit_requested = false;
        }
        if input.wants_quit platform_quit_requested = true;
        SDL_Delay(1);
    }
}
