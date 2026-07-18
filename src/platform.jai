#import "Basic";
#import "Algebra";
#load "webgpu_wgpu.jai";

// This file is the only boundary the game is allowed to use for host services.
// Frame_Input is value data: it can be copied verbatim into a replay stream.

MAX_KEYS :: 256;
MAX_ASYNC_EVENTS :: 64;
MAX_EVENT_BYTES :: 16 * 1024;

KEY_MOVE_UP    :: 0;
KEY_MOVE_LEFT  :: 1;
KEY_MOVE_DOWN  :: 2;
KEY_MOVE_RIGHT :: 3;

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

Asset_Request_Handle :: u32;

Asset_Request_State :: enum u8 {
    EMPTY;
    PENDING;
    READY;
    FAILED;
}

Asset_Request_Status :: struct {
    state: Asset_Request_State;
    bytes_received: u64;
    bytes_total: u64;
    error_code: u32;
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
    capture_frame: bool;
    async_events: [] Async_Event; // Allocated from the current frame arena.
}

WebGPU_Api :: struct {
    // These names intentionally match the WebGPU C API. The platform owns their implementation.
    wgpuCreateInstance: WGPUProcCreateInstance = null;
    wgpuInstanceCreateSurface: WGPUProcInstanceCreateSurface = null;
    wgpuInstanceProcessEvents: WGPUProcInstanceProcessEvents = null;
    wgpuInstanceRequestAdapter: WGPUProcInstanceRequestAdapter = null;
    wgpuAdapterRequestDevice: WGPUProcAdapterRequestDevice = null;
    wgpuDeviceGetQueue: WGPUProcDeviceGetQueue = null;
    wgpuDeviceCreateBuffer: WGPUProcDeviceCreateBuffer = null;
    wgpuDeviceCreateTexture: WGPUProcDeviceCreateTexture = null;
    wgpuDeviceCreateBindGroup: WGPUProcDeviceCreateBindGroup = null;
    wgpuDeviceCreateShaderModule: WGPUProcDeviceCreateShaderModule = null;
    wgpuDeviceCreateRenderPipeline: WGPUProcDeviceCreateRenderPipeline = null;
    wgpuDeviceCreateCommandEncoder: WGPUProcDeviceCreateCommandEncoder = null;
    wgpuCommandEncoderBeginRenderPass: WGPUProcCommandEncoderBeginRenderPass = null;
    wgpuCommandEncoderCopyTextureToBuffer: WGPUProcCommandEncoderCopyTextureToBuffer = null;
    wgpuCommandEncoderFinish: WGPUProcCommandEncoderFinish = null;
    wgpuRenderPassEncoderSetPipeline: WGPUProcRenderPassEncoderSetPipeline = null;
    wgpuRenderPassEncoderSetBindGroup: WGPUProcRenderPassEncoderSetBindGroup = null;
    wgpuRenderPassEncoderDraw: WGPUProcRenderPassEncoderDraw = null;
    wgpuRenderPassEncoderEnd: WGPUProcRenderPassEncoderEnd = null;
    wgpuQueueSubmit: WGPUProcQueueSubmit = null;
    wgpuQueueWriteBuffer: WGPUProcQueueWriteBuffer = null;
    wgpuBufferMapAsync: WGPUProcBufferMapAsync = null;
    wgpuBufferGetConstMappedRange: WGPUProcBufferGetConstMappedRange = null;
    wgpuBufferUnmap: WGPUProcBufferUnmap = null;
    wgpuBufferRelease: WGPUProcBufferRelease = null;
    wgpuRenderPipelineGetBindGroupLayout: WGPUProcRenderPipelineGetBindGroupLayout = null;
    wgpuSurfaceConfigure: WGPUProcSurfaceConfigure = null;
    wgpuSurfaceGetCurrentTexture: WGPUProcSurfaceGetCurrentTexture = null;
    wgpuSurfacePresent: WGPUProcSurfacePresent = null;
    wgpuTextureCreateView: WGPUProcTextureCreateView = null;
    wgpuTextureRelease: WGPUProcTextureRelease = null;
    wgpuTextureViewRelease: WGPUProcTextureViewRelease = null;
    wgpuRenderPassEncoderRelease: WGPUProcRenderPassEncoderRelease = null;
    wgpuCommandEncoderRelease: WGPUProcCommandEncoderRelease = null;
    wgpuCommandBufferRelease: WGPUProcCommandBufferRelease = null;
}

Platform_System_Api :: struct {
    log: #type (text: [] u8) = null;
    request_quit: #type () = null;
    write_file: #type (path: [] u8, data: [] u8) -> bool = null;
    capture_rgba: #type (width: u32, height: u32, rgba: [] u8) -> bool = null;
    try_get_asset_blob: #type () -> [] u8 = null;
    asset_request_async: #type (path: [] u8) -> Asset_Request_Handle = null;
    asset_get_status: #type (handle: Asset_Request_Handle) -> Asset_Request_Status = null;
    asset_take: #type (handle: Asset_Request_Handle, allocator: Allocator) -> [] u8 = null;
    read_file_async: #type (path: [] u8, request_id: u32) = null;
    send_websocket: #type (data: [] u8, destination: u32) = null;
}

Platform :: struct {
    system: Platform_System_Api;
    gpu: WebGPU_Api;
}
