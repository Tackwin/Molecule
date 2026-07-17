#import "platform";
#import "SDL";
Win32 :: #import "Windows";

wgpu_native :: #library "../../IceEscapeReference/lib/wgpu_native";

wgpuCreateInstance :: (d: *WGPUInstanceDescriptor) -> WGPUInstance #foreign wgpu_native;
wgpuInstanceProcessEvents :: (i: WGPUInstance) #foreign wgpu_native;
wgpuInstanceRequestAdapter :: (i: WGPUInstance, o: *WGPURequestAdapterOptions, c: WGPURequestAdapterCallbackInfo) -> WGPUFuture #foreign wgpu_native;
wgpuAdapterRequestDevice :: (a: WGPUAdapter, d: *WGPUDeviceDescriptor, c: WGPURequestDeviceCallbackInfo) -> WGPUFuture #foreign wgpu_native;
wgpuDeviceGetQueue :: (d: WGPUDevice) -> WGPUQueue #foreign wgpu_native;
wgpuDeviceCreateShaderModule :: (d: WGPUDevice, x: *WGPUShaderModuleDescriptor) -> WGPUShaderModule #foreign wgpu_native;
wgpuDeviceCreateRenderPipeline :: (d: WGPUDevice, x: *WGPURenderPipelineDescriptor) -> WGPURenderPipeline #foreign wgpu_native;
wgpuSurfaceConfigure :: (s: WGPUSurface, c: *WGPUSurfaceConfiguration) #foreign wgpu_native;
wgpuSurfaceGetCurrentTexture :: (s: WGPUSurface, o: *WGPUSurfaceTexture) #foreign wgpu_native;
wgpuTextureCreateView :: (t: WGPUTexture, d: *WGPUTextureViewDescriptor) -> WGPUTextureView #foreign wgpu_native;
wgpuDeviceCreateCommandEncoder :: (d: WGPUDevice, x: *WGPUCommandEncoderDescriptor) -> WGPUCommandEncoder #foreign wgpu_native;
wgpuCommandEncoderBeginRenderPass :: (e: WGPUCommandEncoder, d: *WGPURenderPassDescriptor) -> WGPURenderPassEncoder #foreign wgpu_native;
wgpuRenderPassEncoderSetPipeline :: (p: WGPURenderPassEncoder, x: WGPURenderPipeline) #foreign wgpu_native;
wgpuRenderPassEncoderDraw :: (p: WGPURenderPassEncoder, v: u32, n: u32, f: u32, i: u32) #foreign wgpu_native;
wgpuRenderPassEncoderEnd :: (p: WGPURenderPassEncoder) #foreign wgpu_native;
wgpuCommandEncoderFinish :: (e: WGPUCommandEncoder, d: *WGPUCommandBufferDescriptor) -> WGPUCommandBuffer #foreign wgpu_native;
wgpuQueueSubmit :: (q: WGPUQueue, n: u64, c: *WGPUCommandBuffer) #foreign wgpu_native;
wgpuSurfacePresent :: (s: WGPUSurface) -> WGPUStatus #foreign wgpu_native;

win32_wgpuInstanceCreateSurface :: (instance: WGPUInstance, descriptor: *WGPUSurfaceDescriptor) -> WGPUSurface #c_call {
    push_context, defer_pop;
    wgpuInstanceCreateSurface :: (i: WGPUInstance, d: *WGPUSurfaceDescriptor) -> WGPUSurface #foreign wgpu_native;
    info: SDL_SysWMinfo = .{};
    SDL_VERSION(*info.version);
    SDL_GetWindowWMInfo(win32_webgpu_window, *info);
    source: WGPUSurfaceSourceWindowsHWND = .{};
    source.chain.sType = .SurfaceSourceWindowsHWND;
    source.chain.next = null;
    source.hinstance = Win32.GetModuleHandleW(null);
    source.hwnd = xx info.info.win.window;
    native_descriptor: WGPUSurfaceDescriptor = .{};
    if descriptor {
        native_descriptor = descriptor.*;
    }
    native_descriptor.nextInChain = xx *source.chain;
    return wgpuInstanceCreateSurface(instance, *native_descriptor);
}

win32_webgpu_window: *SDL_Window;

install_win32_webgpu :: (gpu: *WebGPU_Api, window: *SDL_Window) {
    win32_webgpu_window = window;
    gpu.wgpuCreateInstance = wgpuCreateInstance;
    gpu.wgpuInstanceCreateSurface = win32_wgpuInstanceCreateSurface;
    gpu.wgpuInstanceProcessEvents = wgpuInstanceProcessEvents;
    gpu.wgpuInstanceRequestAdapter = wgpuInstanceRequestAdapter;
    gpu.wgpuAdapterRequestDevice = wgpuAdapterRequestDevice;
    gpu.wgpuDeviceGetQueue = wgpuDeviceGetQueue;
    gpu.wgpuDeviceCreateShaderModule = wgpuDeviceCreateShaderModule;
    gpu.wgpuDeviceCreateRenderPipeline = wgpuDeviceCreateRenderPipeline;
    gpu.wgpuSurfaceConfigure = wgpuSurfaceConfigure;
    gpu.wgpuSurfaceGetCurrentTexture = wgpuSurfaceGetCurrentTexture;
    gpu.wgpuTextureCreateView = wgpuTextureCreateView;
    gpu.wgpuDeviceCreateCommandEncoder = wgpuDeviceCreateCommandEncoder;
    gpu.wgpuCommandEncoderBeginRenderPass = wgpuCommandEncoderBeginRenderPass;
    gpu.wgpuRenderPassEncoderSetPipeline = wgpuRenderPassEncoderSetPipeline;
    gpu.wgpuRenderPassEncoderDraw = wgpuRenderPassEncoderDraw;
    gpu.wgpuRenderPassEncoderEnd = wgpuRenderPassEncoderEnd;
    gpu.wgpuCommandEncoderFinish = wgpuCommandEncoderFinish;
    gpu.wgpuQueueSubmit = wgpuQueueSubmit;
    gpu.wgpuSurfacePresent = wgpuSurfacePresent;
}
