#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "Algebra";
#import "platform";

kernel32 :: #library,system "kernel32";

DisconnectNamedPipe :: (pipe: HANDLE) -> BOOL #foreign kernel32;

MOLECULE_CONTROL_PIPE_NAME :: "\\\\.\\pipe\\MoleculeControl";

Win32_Control :: struct {
    pipe: HANDLE = INVALID_HANDLE_VALUE;
    connected: bool;
    paused: bool;
    step_frames: u32;
    quit_requested: bool;
    movement_down: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    movement_pressed: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    movement_released: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    capture_enabled: bool;
    capture_requested: bool;
    has_mouse_position: bool;
    mouse_position: V2i;
    mouse_delta: V2i;
    wheel_steps: s32;
}

win32_control_open :: (control: *Win32_Control) -> bool {
    pipe_name := utf8_to_wide(MOLECULE_CONTROL_PIPE_NAME,, allocator = temp);
    control.pipe = CreateNamedPipeW(
        pipe_name,
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
        1,
        4096,
        4096,
        0,
        null
    );
    return control.pipe != INVALID_HANDLE_VALUE;
}

win32_control_close_client :: (control: *Win32_Control) {
    if control.connected {
        DisconnectNamedPipe(control.pipe);
    }
    control.connected = false;
}

win32_control_reset_pipe :: (control: *Win32_Control) {
    win32_control_close_client(control);
}

win32_control_shutdown :: (control: *Win32_Control) {
    win32_control_close_client(control);
    if control.pipe != INVALID_HANDLE_VALUE {
        CloseHandle(control.pipe);
        control.pipe = INVALID_HANDLE_VALUE;
    }
}

win32_control_next_token :: (line: *string) -> string {
    while line.count > 0 && (line.data[0] == #char " " || line.data[0] == #char "\t" || line.data[0] == #char "\r" || line.data[0] == #char "\n") {
        line.data += 1;
        line.count -= 1;
    }
    result := line.*;
    while line.count > 0 && line.data[0] != #char " " && line.data[0] != #char "\t" && line.data[0] != #char "\r" && line.data[0] != #char "\n" {
        line.data += 1;
        line.count -= 1;
    }
    result.count -= line.count;
    return result;
}

win32_control_key_index :: (key: string) -> s32 {
    if key == "z" || key == "up" {
        return KEY_MOVE_UP;
    }
    if key == "q" || key == "left" {
        return KEY_MOVE_LEFT;
    }
    if key == "s" || key == "down" {
        return KEY_MOVE_DOWN;
    }
    if key == "d" || key == "right" {
        return KEY_MOVE_RIGHT;
    }
    if key == "f8" {
        return KEY_TOGGLE_GUI_DEMO;
    }
    return -1;
}

win32_control_apply_command :: (control: *Win32_Control, command: string) -> string {
    remaining := command;
    verb := win32_control_next_token(*remaining);
    if verb == "pause" {
        control.paused = true;
        return "ok paused\n";
    }
    if verb == "resume" {
        control.paused = false;
        control.step_frames = 0;
        return "ok resumed\n";
    }
    if verb == "step" {
        frame_token := win32_control_next_token(*remaining);
        frame_count, parsed, _ := string_to_int(frame_token);
        if !parsed || frame_count <= 0 {
            return "error expected a positive frame count\n";
        }
        control.paused = true;
        control.step_frames += cast(u32) frame_count;
        return tprint("ok step_frames=%\n", control.step_frames);
    }
    if verb == "status" {
        return tprint(
            "ok paused=% step_frames=% capture_enabled=%\n",
            control.paused,
            control.step_frames,
            control.capture_enabled
        );
    }
    if verb == "quit" {
        control.quit_requested = true;
        return "ok quit\n";
    }
    if verb == "capture" {
        action := win32_control_next_token(*remaining);
        if action == "once" {
            control.capture_requested = true;
        }
        if action == "start" {
            control.capture_enabled = true;
        }
        if action == "stop" {
            control.capture_enabled = false;
        }
        return tprint("ok capture_enabled=%\n", control.capture_enabled);
    }
    if verb == "wheel" {
        step_token := win32_control_next_token(*remaining);
        step_count, parsed, _ := string_to_int(step_token);
        if !parsed {
            return "error expected wheel steps\n";
        }
        control.wheel_steps += cast(s32) step_count;
        return "ok wheel\n";
    }
    if verb == "mouse" {
        x_token := win32_control_next_token(*remaining);
        y_token := win32_control_next_token(*remaining);
        x, x_ok, _ := string_to_int(x_token);
        y, y_ok, _ := string_to_int(y_token);
        if !x_ok || !y_ok {
            return "error expected mouse x y\n";
        }
        new_position: V2i = .{ cast(s32) x, cast(s32) y };
        if control.has_mouse_position {
            control.mouse_delta += new_position - control.mouse_position;
        }
        control.mouse_position = new_position;
        control.has_mouse_position = true;
        return "ok mouse\n";
    }
    if verb == "mouse_delta" {
        x_token := win32_control_next_token(*remaining);
        y_token := win32_control_next_token(*remaining);
        x, x_ok, _ := string_to_int(x_token);
        y, y_ok, _ := string_to_int(y_token);
        if !x_ok || !y_ok {
            return "error expected mouse delta x y\n";
        }
        delta: V2i = .{ cast(s32) x, cast(s32) y };
        control.mouse_delta += delta;
        control.mouse_position += delta;
        control.has_mouse_position = true;
        return "ok mouse_delta\n";
    }
    if verb == "key" {
        key := win32_control_next_token(*remaining);
        action := win32_control_next_token(*remaining);
        index := win32_control_key_index(key);
        if index < 0 {
            return "error unknown key\n";
        }
        if action == "down" && !control.movement_down[index] {
            control.movement_down[index] = true;
            control.movement_pressed[index] = true;
        }
        if action == "up" && control.movement_down[index] {
            control.movement_down[index] = false;
            control.movement_released[index] = true;
        }
        if action != "down" && action != "up" {
            return "error expected key action down or up\n";
        }
        return "ok key\n";
    }
    return "error unknown command\n";
}

win32_control_poll :: (control: *Win32_Control) {
    if control.pipe == INVALID_HANDLE_VALUE {
        return;
    }
    if !control.connected {
        if ConnectNamedPipe(control.pipe, null) {
            control.connected = true;
        } else {
            error := GetLastError();
            if error == ERROR_PIPE_CONNECTED {
                control.connected = true;
            }
        }
    }
    if !control.connected {
        return;
    }

    command_bytes: [4096] u8;
    bytes_read: DWORD;
    if ReadFile(control.pipe, *command_bytes, command_bytes.count, *bytes_read, null) {
        command: string = .{ data = *command_bytes[0], count = bytes_read };
        command = trim(command, " \t\r\n");
        response := win32_control_apply_command(control, command);
        bytes_written: DWORD;
        WriteFile(control.pipe, response.data, cast(DWORD) response.count, *bytes_written, null);
        FlushFileBuffers(control.pipe);
        win32_control_close_client(control);
        return;
    }

    error := GetLastError();
    if error == ERROR_BROKEN_PIPE {
        win32_control_reset_pipe(control);
    }
}

win32_control_merge_input :: (control: *Win32_Control, input: *Frame_Input) {
    for 0..control.movement_down.count - 1 {
        input.keyboard.down[it] = input.keyboard.down[it] || control.movement_down[it];
        input.keyboard.pressed[it] = input.keyboard.pressed[it] || control.movement_pressed[it];
        input.keyboard.released[it] = input.keyboard.released[it] || control.movement_released[it];
        control.movement_pressed[it] = false;
        control.movement_released[it] = false;
    }
    if control.has_mouse_position {
        input.mouse.position_pixels = control.mouse_position;
    }
    input.mouse.delta_pixels += control.mouse_delta;
    control.mouse_delta = .{};
    input.mouse.wheel_steps += control.wheel_steps;
    control.wheel_steps = 0;
    input.capture_frame = control.capture_enabled || control.capture_requested;
    control.capture_requested = false;
    input.wants_quit = input.wants_quit || control.quit_requested;
    control.quit_requested = false;
}
