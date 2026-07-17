#import "Basic";
#import "Algebra";

// This file is the only boundary the game is allowed to use for host services.
// Frame_Input is value data: it can be copied verbatim into a replay stream.

MAX_KEYS :: 256;
MAX_ASYNC_EVENTS :: 64;
MAX_EVENT_BYTES :: 16 * 1024;

Async_Event_Kind :: enum u8 {
    NONE;
    WEBSOCKET_MESSAGE;
    FILE_OPENED;
    FILE_CHANGED;
    MCP_COMMAND;
}

Async_Event :: struct {
    kind: Async_Event_Kind;
    payload: [] u8;
    source: u32;
}

// Hosts allocate all variable-size frame data from this bump arena and reset it before
// building the next Frame_Input. The game may read this memory for the current call only.
// A recorder copies the arena bytes plus the input's slice offsets into its own format.
Frame_Arena :: struct {
    memory: [] u8;
    used: u64;
}

frame_arena_reset :: (arena: *Frame_Arena) { arena.used = 0; }
frame_arena_allocate :: (arena: *Frame_Arena, byte_count: u64) -> [] u8 {
    if arena.used + byte_count > arena.memory.count return .{};
    result: [] u8;
    result.data = arena.memory.data + arena.used;
    result.count = byte_count.(int);
    arena.used += byte_count;
    return result;
}

Keyboard_State :: struct {
    down: [MAX_KEYS] bool;
    pressed: [MAX_KEYS] bool;
    released: [MAX_KEYS] bool;
}

Mouse_State :: struct {
    position_pixels: V2i;
    delta_pixels: V2i;
    wheel_steps: s32;
    buttons_down: u8;
    buttons_pressed: u8;
    buttons_released: u8;
}

Frame_Input :: struct {
    simulation_delta_seconds: float32;
    window_size_pixels: V2i;
    framebuffer_size_pixels: V2i;
    keyboard: Keyboard_State;
    mouse: Mouse_State;
    wants_quit: bool;
    async_events: [] Async_Event; // Allocated from the current frame arena.
}

// Opaque identifiers make handles host-owned and replay-independent.
Gpu_Handle :: u32;
Gpu_Invalid: Gpu_Handle : 0;

Gpu_Frame :: struct {
    surface_texture: Gpu_Handle;
    surface_view: Gpu_Handle;
    width: u32;
    height: u32;
    valid: bool;
}

WebGPU_Api :: struct {
    // Resource creation/destruction.
    wgpuDeviceCreateBuffer: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateTexture: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateSampler: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateShaderModule: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateBindGroupLayout: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateBindGroup: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreatePipelineLayout: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuDeviceCreateRenderPipeline: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuBufferRelease: #type (buffer: Gpu_Handle) = null;
    wgpuTextureRelease: #type (texture: Gpu_Handle) = null;
    wgpuRenderPipelineRelease: #type (pipeline: Gpu_Handle) = null;

    // Queue and command encoding.
    wgpuQueueWriteBuffer: #type (queue: Gpu_Handle, buffer: Gpu_Handle, offset: u64, data: [] u8) = null;
    wgpuDeviceCreateCommandEncoder: #type (device: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuCommandEncoderBeginRenderPass: #type (encoder: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuRenderPassEncoderSetPipeline: #type (pass: Gpu_Handle, pipeline: Gpu_Handle) = null;
    wgpuRenderPassEncoderSetBindGroup: #type (pass: Gpu_Handle, slot: u32, group: Gpu_Handle) = null;
    wgpuRenderPassEncoderSetVertexBuffer: #type (pass: Gpu_Handle, slot: u32, buffer: Gpu_Handle) = null;
    wgpuRenderPassEncoderSetIndexBuffer: #type (pass: Gpu_Handle, buffer: Gpu_Handle) = null;
    wgpuRenderPassEncoderDraw: #type (pass: Gpu_Handle, vertex_count: u32, instance_count: u32) = null;
    wgpuRenderPassEncoderDrawIndexed: #type (pass: Gpu_Handle, index_count: u32, instance_count: u32) = null;
    wgpuRenderPassEncoderEnd: #type (pass: Gpu_Handle) = null;
    wgpuCommandEncoderFinish: #type (encoder: Gpu_Handle, descriptor_bytes: [] u8) -> Gpu_Handle = null;
    wgpuQueueSubmit: #type (queue: Gpu_Handle, command_buffers: [] Gpu_Handle) = null;

    // Presentation belongs to the host; the game only renders into this frame.
    wgpuSurfaceGetCurrentTexture: #type (surface: Gpu_Handle) -> Gpu_Frame = null;
    wgpuSurfacePresent: #type (surface: Gpu_Handle) = null;
}

Platform_System_Api :: struct {
    log: #type (text: [] u8) = null;
    request_quit: #type () = null;
    read_file_async: #type (path: [] u8, request_id: u32) = null;
    send_websocket: #type (data: [] u8, destination: u32) = null;
}

Platform :: struct {
    system: Platform_System_Api;
    gpu: WebGPU_Api;
}
