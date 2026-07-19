#import "platform";
#import "SDL";
Win32 :: #import "Windows";

wgpu_native :: #library "../../IceEscapeReference/lib/wgpu_native";

wgpuCreateInstance :: (d: *WGPUInstanceDescriptor) -> WGPUInstance #foreign wgpu_native;
wgpuInstanceProcessEvents :: (i: WGPUInstance) #foreign wgpu_native;
wgpuInstanceRelease :: (i: WGPUInstance) #foreign wgpu_native;
wgpuInstanceRequestAdapter :: (i: WGPUInstance, o: *WGPURequestAdapterOptions, c: WGPURequestAdapterCallbackInfo) -> WGPUFuture #foreign wgpu_native;
wgpuAdapterRelease :: (a: WGPUAdapter) #foreign wgpu_native;
wgpuAdapterRequestDevice :: (a: WGPUAdapter, d: *WGPUDeviceDescriptor, c: WGPURequestDeviceCallbackInfo) -> WGPUFuture #foreign wgpu_native;
wgpuDeviceGetQueue :: (d: WGPUDevice) -> WGPUQueue #foreign wgpu_native;
wgpuDeviceRelease :: (d: WGPUDevice) #foreign wgpu_native;
wgpuDeviceCreateBuffer :: (d: WGPUDevice, x: *WGPUBufferDescriptor) -> WGPUBuffer #foreign wgpu_native;
wgpuDeviceCreateTexture :: (d: WGPUDevice, x: *WGPUTextureDescriptor) -> WGPUTexture #foreign wgpu_native;
wgpuDeviceCreateSampler :: (d: WGPUDevice, x: *WGPUSamplerDescriptor) -> WGPUSampler #foreign wgpu_native;
wgpuBufferMapAsync :: (buffer: WGPUBuffer, mode: WGPUMapMode, offset: u64, size: u64, callback: WGPUBufferMapCallbackInfo) -> WGPUFuture #foreign wgpu_native;
wgpuBufferGetConstMappedRange :: (buffer: WGPUBuffer, offset: u64, size: u64) -> *void #foreign wgpu_native;
wgpuBufferUnmap :: (buffer: WGPUBuffer) #foreign wgpu_native;
wgpuBufferRelease :: (buffer: WGPUBuffer) #foreign wgpu_native;
wgpuDeviceCreateBindGroup :: (d: WGPUDevice, x: *WGPUBindGroupDescriptor) -> WGPUBindGroup #foreign wgpu_native;
wgpuBindGroupRelease :: (b: WGPUBindGroup) #foreign wgpu_native;
wgpuDeviceCreateShaderModule :: (d: WGPUDevice, x: *WGPUShaderModuleDescriptor) -> WGPUShaderModule #foreign wgpu_native;
wgpuDeviceCreateRenderPipeline :: (d: WGPUDevice, x: *WGPURenderPipelineDescriptor) -> WGPURenderPipeline #foreign wgpu_native;
wgpuRenderPipelineRelease :: (p: WGPURenderPipeline) #foreign wgpu_native;
wgpuSurfaceConfigure :: (s: WGPUSurface, c: *WGPUSurfaceConfiguration) #foreign wgpu_native;
wgpuSurfaceUnconfigure :: (s: WGPUSurface) #foreign wgpu_native;
wgpuSurfaceGetCurrentTexture :: (s: WGPUSurface, o: *WGPUSurfaceTexture) #foreign wgpu_native;
wgpuSurfaceRelease :: (s: WGPUSurface) #foreign wgpu_native;
wgpuTextureCreateView :: (t: WGPUTexture, d: *WGPUTextureViewDescriptor) -> WGPUTextureView #foreign wgpu_native;
wgpuTextureRelease :: (t: WGPUTexture) #foreign wgpu_native;
wgpuTextureViewRelease :: (v: WGPUTextureView) #foreign wgpu_native;
wgpuDeviceCreateCommandEncoder :: (d: WGPUDevice, x: *WGPUCommandEncoderDescriptor) -> WGPUCommandEncoder #foreign wgpu_native;
wgpuCommandEncoderBeginRenderPass :: (e: WGPUCommandEncoder, d: *WGPURenderPassDescriptor) -> WGPURenderPassEncoder #foreign wgpu_native;
wgpuCommandEncoderCopyTextureToBuffer :: (encoder: WGPUCommandEncoder, source: *WGPUTexelCopyTextureInfo, destination: *WGPUTexelCopyBufferInfo, copy_size: *WGPUExtent3D) #foreign wgpu_native;
wgpuRenderPassEncoderSetPipeline :: (p: WGPURenderPassEncoder, x: WGPURenderPipeline) #foreign wgpu_native;
wgpuRenderPassEncoderSetBindGroup :: (p: WGPURenderPassEncoder, i: u32, g: WGPUBindGroup, c: u64, o: *u32) #foreign wgpu_native;
wgpuRenderPassEncoderDraw :: (p: WGPURenderPassEncoder, v: u32, n: u32, f: u32, i: u32) #foreign wgpu_native;
wgpuRenderPassEncoderEnd :: (p: WGPURenderPassEncoder) #foreign wgpu_native;
wgpuCommandEncoderFinish :: (e: WGPUCommandEncoder, d: *WGPUCommandBufferDescriptor) -> WGPUCommandBuffer #foreign wgpu_native;
wgpuQueueSubmit :: (q: WGPUQueue, n: u64, c: *WGPUCommandBuffer) #foreign wgpu_native;
wgpuQueueRelease :: (q: WGPUQueue) #foreign wgpu_native;
wgpuQueueWriteBuffer :: (q: WGPUQueue, b: WGPUBuffer, o: u64, d: *void, s: u64) #foreign wgpu_native;
wgpuQueueWriteTexture :: (q: WGPUQueue, d: *WGPUTexelCopyTextureInfo, data: *void, size: u64, l: *WGPUTexelCopyBufferLayout, e: *WGPUExtent3D) #foreign wgpu_native;
wgpuSamplerRelease :: (sampler: WGPUSampler) #foreign wgpu_native;
wgpuRenderPipelineGetBindGroupLayout :: (p: WGPURenderPipeline, i: u32) -> WGPUBindGroupLayout #foreign wgpu_native;
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
    gpu.wgpuInstanceRelease = wgpuInstanceRelease;
    gpu.wgpuInstanceRequestAdapter = wgpuInstanceRequestAdapter;
    gpu.wgpuAdapterRequestDevice = wgpuAdapterRequestDevice;
    gpu.wgpuAdapterRelease = wgpuAdapterRelease;
    gpu.wgpuDeviceGetQueue = wgpuDeviceGetQueue;
    gpu.wgpuDeviceRelease = wgpuDeviceRelease;
    gpu.wgpuDeviceCreateBuffer = wgpuDeviceCreateBuffer;
    gpu.wgpuDeviceCreateTexture = wgpuDeviceCreateTexture;
    gpu.wgpuDeviceCreateSampler = wgpuDeviceCreateSampler;
    gpu.wgpuBufferMapAsync = wgpuBufferMapAsync;
    gpu.wgpuBufferGetConstMappedRange = wgpuBufferGetConstMappedRange;
    gpu.wgpuBufferUnmap = wgpuBufferUnmap;
    gpu.wgpuBufferRelease = wgpuBufferRelease;
    gpu.wgpuDeviceCreateBindGroup = wgpuDeviceCreateBindGroup;
    gpu.wgpuBindGroupRelease = wgpuBindGroupRelease;
    gpu.wgpuDeviceCreateShaderModule = wgpuDeviceCreateShaderModule;
    gpu.wgpuDeviceCreateRenderPipeline = wgpuDeviceCreateRenderPipeline;
    gpu.wgpuRenderPipelineRelease = wgpuRenderPipelineRelease;
    gpu.wgpuSurfaceConfigure = wgpuSurfaceConfigure;
    gpu.wgpuSurfaceUnconfigure = wgpuSurfaceUnconfigure;
    gpu.wgpuSurfaceGetCurrentTexture = wgpuSurfaceGetCurrentTexture;
    gpu.wgpuSurfaceRelease = wgpuSurfaceRelease;
    gpu.wgpuTextureCreateView = wgpuTextureCreateView;
    gpu.wgpuTextureRelease = wgpuTextureRelease;
    gpu.wgpuTextureViewRelease = wgpuTextureViewRelease;
    gpu.wgpuDeviceCreateCommandEncoder = wgpuDeviceCreateCommandEncoder;
    gpu.wgpuCommandEncoderBeginRenderPass = wgpuCommandEncoderBeginRenderPass;
    gpu.wgpuCommandEncoderCopyTextureToBuffer = wgpuCommandEncoderCopyTextureToBuffer;
    gpu.wgpuRenderPassEncoderSetPipeline = wgpuRenderPassEncoderSetPipeline;
    gpu.wgpuRenderPassEncoderSetBindGroup = wgpuRenderPassEncoderSetBindGroup;
    gpu.wgpuRenderPassEncoderDraw = wgpuRenderPassEncoderDraw;
    gpu.wgpuRenderPassEncoderEnd = wgpuRenderPassEncoderEnd;
    gpu.wgpuCommandEncoderFinish = wgpuCommandEncoderFinish;
    gpu.wgpuQueueSubmit = wgpuQueueSubmit;
    gpu.wgpuQueueRelease = wgpuQueueRelease;
    gpu.wgpuQueueWriteBuffer = wgpuQueueWriteBuffer;
    gpu.wgpuQueueWriteTexture = wgpuQueueWriteTexture;
    gpu.wgpuRenderPipelineGetBindGroupLayout = wgpuRenderPipelineGetBindGroupLayout;
    gpu.wgpuSurfacePresent = wgpuSurfacePresent;
    gpu.wgpuSamplerRelease = wgpuSamplerRelease;
}
