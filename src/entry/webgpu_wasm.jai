#import "platform";

// Browser-only implementation of the Platform.gpu table. Each function only
// packs a WebGPU C descriptor into linear memory and forwards it to JavaScript.

wasm_wgpuCreateInstance :: (descriptor: *WGPUInstanceDescriptor) -> WGPUInstance #c_call {
    jsCreateInstance :: (params: *void, returns: *void) #foreign;
    result: WGPUInstance;
    jsCreateInstance(null, *result);
    return result;
}

wasm_wgpuInstanceCreateSurface :: (
    instance: WGPUInstance, descriptor: *WGPUSurfaceDescriptor
) -> WGPUSurface #c_call {
    jsInstanceCreateSurface :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        instance: WGPUInstance;
        descriptor: *WGPUSurfaceDescriptor;
    }
    params: Params;
    params.instance = instance;
    params.descriptor = descriptor;
    result: WGPUSurface;
    jsInstanceCreateSurface(*params, *result);
    return result;
}

wasm_wgpuInstanceRequestAdapter :: (
    instance: WGPUInstance, options: *WGPURequestAdapterOptions,
    callback_info: WGPURequestAdapterCallbackInfo
) -> WGPUFuture #c_call {
    jsInstanceRequestAdapter :: (params: *void, returns: *void) #foreign;
    result: WGPUAdapter;
    jsInstanceRequestAdapter(null, *result);
    callback_info.callback(.Success, result, .{}, callback_info.userdata1, callback_info.userdata2);
    return .{};
}

wasm_wgpuAdapterRequestDevice :: (
    adapter: WGPUAdapter, descriptor: *WGPUDeviceDescriptor,
    callback_info: WGPURequestDeviceCallbackInfo
) -> WGPUFuture #c_call {
    jsAdapterRequestDevice :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        adapter: WGPUAdapter;
        descriptor: *WGPUDeviceDescriptor;
    }
    params: Params;
    params.adapter = adapter;
    params.descriptor = descriptor;
    result: WGPUDevice;
    jsAdapterRequestDevice(*params, *result);
    callback_info.callback(.Success, result, .{}, callback_info.userdata1, callback_info.userdata2);
    return .{};
}

wasm_wgpuDeviceGetQueue :: (device: WGPUDevice) -> WGPUQueue #c_call {
    jsDeviceGetQueue :: (params: *void, returns: *void) #foreign;
    result: WGPUQueue;
    jsDeviceGetQueue(*device, *result);
    return result;
}

wasm_wgpuDeviceCreateShaderModule :: (
    device: WGPUDevice, descriptor: *WGPUShaderModuleDescriptor
) -> WGPUShaderModule #c_call {
    jsDeviceCreateShaderModule :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        device: WGPUDevice;
        descriptor: *WGPUShaderModuleDescriptor;
    }
    params: Params;
    params.device = device;
    params.descriptor = descriptor;
    result: WGPUShaderModule;
    jsDeviceCreateShaderModule(*params, *result);
    return result;
}

wasm_wgpuDeviceCreateRenderPipeline :: (
    device: WGPUDevice, descriptor: *WGPURenderPipelineDescriptor
) -> WGPURenderPipeline #c_call {
    jsDeviceCreateRenderPipeline :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        device: WGPUDevice;
        descriptor: *WGPURenderPipelineDescriptor;
    }
    params: Params;
    params.device = device;
    params.descriptor = descriptor;
    result: WGPURenderPipeline;
    jsDeviceCreateRenderPipeline(*params, *result);
    return result;
}

wasm_wgpuSurfaceConfigure :: (surface: WGPUSurface, config: *WGPUSurfaceConfiguration) #c_call {
    jsSurfaceConfigure :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        surface: WGPUSurface;
        config: *WGPUSurfaceConfiguration;
    }
    params: Params;
    params.surface = surface;
    params.config = config;
    jsSurfaceConfigure(*params, null);
}

wasm_wgpuSurfaceGetCurrentTexture :: (surface: WGPUSurface, output: *WGPUSurfaceTexture) #c_call {
    jsSurfaceGetCurrentTexture :: (params: *void, returns: *void) #foreign;
    jsSurfaceGetCurrentTexture(*surface, output);
}

wasm_wgpuTextureCreateView :: (
    texture: WGPUTexture, descriptor: *WGPUTextureViewDescriptor
) -> WGPUTextureView #c_call {
    jsTextureCreateView :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        texture: WGPUTexture;
        descriptor: *WGPUTextureViewDescriptor;
    }
    params: Params;
    params.texture = texture;
    params.descriptor = descriptor;
    result: WGPUTextureView;
    jsTextureCreateView(*params, *result);
    return result;
}

wasm_wgpuDeviceCreateCommandEncoder :: (
    device: WGPUDevice, descriptor: *WGPUCommandEncoderDescriptor
) -> WGPUCommandEncoder #c_call {
    jsDeviceCreateCommandEncoder :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        device: WGPUDevice;
        descriptor: *WGPUCommandEncoderDescriptor;
    }
    params: Params;
    params.device = device;
    params.descriptor = descriptor;
    result: WGPUCommandEncoder;
    jsDeviceCreateCommandEncoder(*params, *result);
    return result;
}

wasm_wgpuCommandEncoderBeginRenderPass :: (
    encoder: WGPUCommandEncoder, descriptor: *WGPURenderPassDescriptor
) -> WGPURenderPassEncoder #c_call {
    jsCommandEncoderBeginRenderPass :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        encoder: WGPUCommandEncoder;
        descriptor: *WGPURenderPassDescriptor;
    }
    params: Params;
    params.encoder = encoder;
    params.descriptor = descriptor;
    result: WGPURenderPassEncoder;
    jsCommandEncoderBeginRenderPass(*params, *result);
    return result;
}

wasm_wgpuRenderPassEncoderSetPipeline :: (pass: WGPURenderPassEncoder, pipeline: WGPURenderPipeline) #c_call {
    jsRenderPassEncoderSetPipeline :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        pass: WGPURenderPassEncoder;
        pipeline: WGPURenderPipeline;
    }
    params: Params;
    params.pass = pass;
    params.pipeline = pipeline;
    jsRenderPassEncoderSetPipeline(*params, null);
}

wasm_wgpuRenderPassEncoderDraw :: (
    pass: WGPURenderPassEncoder, vertices: u32, instances: u32, first_vertex: u32, first_instance: u32
) #c_call {
    jsRenderPassEncoderDraw :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        pass: WGPURenderPassEncoder;
        vertices: u32;
        instances: u32;
        first_vertex: u32;
        first_instance: u32;
    }
    params: Params;
    params.pass = pass;
    params.vertices = vertices;
    params.instances = instances;
    params.first_vertex = first_vertex;
    params.first_instance = first_instance;
    jsRenderPassEncoderDraw(*params, null);
}

wasm_wgpuRenderPassEncoderEnd :: (pass: WGPURenderPassEncoder) #c_call {
    jsRenderPassEncoderEnd :: (params: *void, returns: *void) #foreign;
    jsRenderPassEncoderEnd(*pass, null);
}

wasm_wgpuCommandEncoderFinish :: (
    encoder: WGPUCommandEncoder, descriptor: *WGPUCommandBufferDescriptor
) -> WGPUCommandBuffer #c_call {
    jsCommandEncoderFinish :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        encoder: WGPUCommandEncoder;
        descriptor: *WGPUCommandBufferDescriptor;
    }
    params: Params;
    params.encoder = encoder;
    params.descriptor = descriptor;
    result: WGPUCommandBuffer;
    jsCommandEncoderFinish(*params, *result);
    return result;
}

wasm_wgpuQueueSubmit :: (queue: WGPUQueue, count: u64, commands: *WGPUCommandBuffer) #c_call {
    jsQueueSubmit :: (params: *void, returns: *void) #foreign;
    Params :: struct {
        queue: WGPUQueue;
        count: u64;
        commands: *WGPUCommandBuffer;
    }
    params: Params;
    params.queue = queue;
    params.count = count;
    params.commands = commands;
    jsQueueSubmit(*params, null);
}

wasm_wgpuSurfacePresent :: (surface: WGPUSurface) -> WGPUStatus #c_call {
    jsSurfacePresent :: (params: *void, returns: *void) #foreign;
    jsSurfacePresent(*surface, null);
    return .Success;
}

install_wasm_webgpu :: (gpu: *WebGPU_Api) {
    gpu.wgpuCreateInstance = wasm_wgpuCreateInstance;
    gpu.wgpuInstanceCreateSurface = wasm_wgpuInstanceCreateSurface;
    gpu.wgpuInstanceRequestAdapter = wasm_wgpuInstanceRequestAdapter;
    gpu.wgpuAdapterRequestDevice = wasm_wgpuAdapterRequestDevice;
    gpu.wgpuDeviceGetQueue = wasm_wgpuDeviceGetQueue;
    gpu.wgpuDeviceCreateShaderModule = wasm_wgpuDeviceCreateShaderModule;
    gpu.wgpuDeviceCreateRenderPipeline = wasm_wgpuDeviceCreateRenderPipeline;
    gpu.wgpuSurfaceConfigure = wasm_wgpuSurfaceConfigure;
    gpu.wgpuSurfaceGetCurrentTexture = wasm_wgpuSurfaceGetCurrentTexture;
    gpu.wgpuTextureCreateView = wasm_wgpuTextureCreateView;
    gpu.wgpuDeviceCreateCommandEncoder = wasm_wgpuDeviceCreateCommandEncoder;
    gpu.wgpuCommandEncoderBeginRenderPass = wasm_wgpuCommandEncoderBeginRenderPass;
    gpu.wgpuRenderPassEncoderSetPipeline = wasm_wgpuRenderPassEncoderSetPipeline;
    gpu.wgpuRenderPassEncoderDraw = wasm_wgpuRenderPassEncoderDraw;
    gpu.wgpuRenderPassEncoderEnd = wasm_wgpuRenderPassEncoderEnd;
    gpu.wgpuCommandEncoderFinish = wasm_wgpuCommandEncoderFinish;
    gpu.wgpuQueueSubmit = wasm_wgpuQueueSubmit;
    gpu.wgpuSurfacePresent = wasm_wgpuSurfacePresent;
}
