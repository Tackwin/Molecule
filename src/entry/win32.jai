#import "Basic";
#import "SDL";
#import "platform";
#import "game";
#import "renderer";
#load "webgpu_win32.jai";

platform_quit_requested := false;

win32_request_quit :: () { platform_quit_requested = true; }

make_win32_platform :: () -> Platform {
    platform: Platform;
    platform.system.request_quit = win32_request_quit;
    return platform;
}

poll_win32_input :: (window: *SDL_Window, input: *Frame_Input) {
    // Reset transient edge state; down state survives from the preceding frame.
    for 0..MAX_KEYS-1 {
        input.keyboard.pressed[it] = false;
        input.keyboard.released[it] = false;
    }
    input.mouse.delta_pixels = .{};
    input.mouse.wheel_steps = 0;
    input.mouse.buttons_pressed = 0;
    input.mouse.buttons_released = 0;
    input.wants_quit = false;

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
                if key == SDLK_ESCAPE input.wants_quit = true;
            case SDL_KEYUP;
                key := event.key.keysym.sym;
                if key >= 0 && key < MAX_KEYS {
                    input.keyboard.down[key] = false;
                    input.keyboard.released[key] = true;
                }
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
    game: Game_State;
    game_init(*game, 0x4d6f6c6563756c65);
    renderer: Renderer;
    renderer_init(*renderer, *platform, 1280, 720);

    input: Frame_Input;
    while !platform_quit_requested {
        poll_win32_input(window, *input);
        game_tick(*game, *input, *platform);
        renderer_draw(*renderer, *platform);
        if input.wants_quit platform_quit_requested = true;
        SDL_Delay(1);
    }
}
