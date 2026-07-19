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
    quit_requested: bool;
    movement_down: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    movement_pressed: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    movement_released: [KEY_TOGGLE_GUI_DEMO + 1] bool;
    capture_enabled: bool;
    capture_requested: bool;
    has_mouse_position: bool;
    mouse_position: V2i;
    mouse_delta: V2i;
}

win32_control_open :: (control: *Win32_Control) -> bool {
    pipe_name := utf8_to_wide(MOLECULE_CONTROL_PIPE_NAME,, allocator = temp);
    control.pipe = CreateNamedPipeW(
        pipe_name,
        PIPE_ACCESS_INBOUND,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
        1,
        0,
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

win32_control_apply_command :: (control: *Win32_Control, command: string) {
    remaining := command;
    verb := win32_control_next_token(*remaining);
    if verb == "pause" {
        control.paused = true;
        return;
    }
    if verb == "resume" {
        control.paused = false;
        return;
    }
    if verb == "quit" {
        control.quit_requested = true;
        return;
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
        return;
    }
    if verb == "mouse" {
        x_token := win32_control_next_token(*remaining);
        y_token := win32_control_next_token(*remaining);
        x, x_ok, _ := string_to_int(x_token);
        y, y_ok, _ := string_to_int(y_token);
        if !x_ok || !y_ok {
            return;
        }
        new_position: V2i = .{ cast(s32) x, cast(s32) y };
        if control.has_mouse_position {
            control.mouse_delta += new_position - control.mouse_position;
        }
        control.mouse_position = new_position;
        control.has_mouse_position = true;
        return;
    }
    if verb == "mouse_delta" {
        x_token := win32_control_next_token(*remaining);
        y_token := win32_control_next_token(*remaining);
        x, x_ok, _ := string_to_int(x_token);
        y, y_ok, _ := string_to_int(y_token);
        if !x_ok || !y_ok {
            return;
        }
        delta: V2i = .{ cast(s32) x, cast(s32) y };
        control.mouse_delta += delta;
        control.mouse_position += delta;
        control.has_mouse_position = true;
        return;
    }
    if verb == "key" {
        key := win32_control_next_token(*remaining);
        action := win32_control_next_token(*remaining);
        index := win32_control_key_index(key);
        if index < 0 {
            return;
        }
        if action == "down" && !control.movement_down[index] {
            control.movement_down[index] = true;
            control.movement_pressed[index] = true;
        }
        if action == "up" && control.movement_down[index] {
            control.movement_down[index] = false;
            control.movement_released[index] = true;
        }
    }
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
        win32_control_apply_command(control, command);
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
    input.capture_frame = control.capture_enabled || control.capture_requested;
    control.capture_requested = false;
    input.wants_quit = input.wants_quit || control.quit_requested;
    control.quit_requested = false;
}
