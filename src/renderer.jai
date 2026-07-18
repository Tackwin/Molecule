#import "Basic";
#import "platform";
#import "Algebra";
#import "Qoi";

Renderer :: struct {
    instance: WGPUInstance;
    adapter: WGPUAdapter;
    device: WGPUDevice;
    queue: WGPUQueue;
    surface: WGPUSurface;
    pipeline: WGPURenderPipeline;
    offset_buffer: WGPUBuffer;
    offset_bind_group: WGPUBindGroup;
    capture_width: u32;
    capture_height: u32;
    capture_enabled: bool;
    capture_supported: bool;
    capture_frame_index: u64;
    capture_rgba: [..] u8;
    capture_pixels: [..] Qoi_Pixel;
    capture_qoi: [..] u8;
    ready: bool;
}

to_wgpu_string :: (text: string) -> WGPUStringView {
    return .{ data = xx text.data, length = xx text.count };
}

adapter_ready :: (
    status: WGPURequestAdapterStatus, adapter: WGPUAdapter, message: WGPUStringView,
    userdata1: *void, userdata2: *void
) #c_call {
    renderer := userdata1.(*Renderer);
    renderer.adapter = adapter;
}

device_ready :: (
    status: WGPURequestDeviceStatus, device: WGPUDevice, message: WGPUStringView,
    userdata1: *void, userdata2: *void
) #c_call {
    renderer := userdata1.(*Renderer);
    renderer.device = device;
}

renderer_capture_start :: (renderer: *Renderer) {
    if renderer.capture_supported {
        renderer.capture_enabled = true;
    }
}

renderer_capture_stop :: (renderer: *Renderer) {
    renderer.capture_enabled = false;
}

renderer_capture_frame :: (renderer: *Renderer, platform: *Platform) {
    if !platform.system.write_file || !platform.system.capture_rgba {
        return;
    }
    pixel_count := cast(u64) renderer.capture_width * renderer.capture_height;
    array_resize(*renderer.capture_rgba, xx (pixel_count * 4));
    if !platform.system.capture_rgba(renderer.capture_width, renderer.capture_height, renderer.capture_rgba) {
        return;
    }
    array_resize(*renderer.capture_pixels, xx pixel_count);
    for y: 0..renderer.capture_height - 1 {
        for x: 0..renderer.capture_width - 1 {
            source_index := (y * renderer.capture_width + x) * 4;
            destination_index := y * renderer.capture_width + x;
            renderer.capture_pixels[destination_index] = .{
                renderer.capture_rgba[source_index + 0],
                renderer.capture_rgba[source_index + 1],
                renderer.capture_rgba[source_index + 2],
                renderer.capture_rgba[source_index + 3],
            };
        }
    }

    max_qoi_bytes := qoi_encoded_max_size(pixel_count);
    array_resize(*renderer.capture_qoi, xx max_qoi_bytes);
    info: Qoi_Image_Info = .{
        width = renderer.capture_width,
        height = renderer.capture_height,
        channels = 4,
        colorspace = 0,
    };
    qoi_bytes, encoded := qoi_encode(info, renderer.capture_pixels, renderer.capture_qoi);
    if !encoded {
        return;
    }
    renderer.capture_qoi.count = xx qoi_bytes;
    path := tprint("captures/frame_%.qoi", renderer.capture_frame_index);
    if platform.system.write_file(.{ data = path.data, count = path.count }, renderer.capture_qoi) {
        renderer.capture_frame_index += 1;
    }
}

renderer_init :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32, shader_bytes: [] u8) {
    // A browser starts without the optional packed asset blob.  Its Store
    // promotes the shader after the asynchronous platform request completes.
    // Until then there is no valid pipeline to create.
    if shader_bytes.count == 0 {
        return;
    }
    gpu := *platform.gpu;
    renderer.instance = gpu.wgpuCreateInstance(null);
    renderer.surface = gpu.wgpuInstanceCreateSurface(renderer.instance, null);

    adapter_info: WGPURequestAdapterCallbackInfo = .{};
    adapter_info.mode = .AllowProcessEvents;
    adapter_info.callback = adapter_ready;
    adapter_info.userdata1 = renderer;
    adapter_options: WGPURequestAdapterOptions = .{};
    adapter_options.compatibleSurface = renderer.surface;
    gpu.wgpuInstanceRequestAdapter(renderer.instance, *adapter_options, adapter_info);
    while !renderer.adapter {
        gpu.wgpuInstanceProcessEvents(renderer.instance);
    }
    if !renderer.adapter return;

    device_info: WGPURequestDeviceCallbackInfo = .{};
    device_info.mode = .AllowProcessEvents;
    device_info.callback = device_ready;
    device_info.userdata1 = renderer;
    device_descriptor: WGPUDeviceDescriptor = .{};
    gpu.wgpuAdapterRequestDevice(renderer.adapter, *device_descriptor, device_info);
    while !renderer.device {
        gpu.wgpuInstanceProcessEvents(renderer.instance);
    }
    if !renderer.device return;
    renderer.queue = gpu.wgpuDeviceGetQueue(renderer.device);

    config: WGPUSurfaceConfiguration = .{};
    config.device = renderer.device;
    config.format = .BGRA8Unorm;
    config.usage = WGPUTextureUsage_RenderAttachment;
    config.width = width;
    config.height = height;
    config.presentMode = .Fifo;
    config.alphaMode = .Opaque;
    gpu.wgpuSurfaceConfigure(renderer.surface, *config);

    source: WGPUShaderSourceWGSL = .{};
    source.chain.sType = .ShaderSourceWGSL;
    source.code = .{ data = shader_bytes.data, length = xx shader_bytes.count };
    shader_descriptor: WGPUShaderModuleDescriptor = .{};
    shader_descriptor.nextInChain = *source.chain;
    shader := gpu.wgpuDeviceCreateShaderModule(renderer.device, *shader_descriptor);

    target: WGPUColorTargetState = .{};
    target.format = .BGRA8Unorm;
    target.writeMask = WGPUColorWriteMask_All;
    fragment: WGPUFragmentState = .{};
    fragment.module = shader;
    fragment.entryPoint = to_wgpu_string("fs");
    fragment.targetCount = 1;
    fragment.targets = *target;
    pipeline_descriptor: WGPURenderPipelineDescriptor = .{};
    pipeline_descriptor.vertex.module = shader;
    pipeline_descriptor.vertex.entryPoint = to_wgpu_string("vs");
    pipeline_descriptor.primitive.topology = .TriangleList;
    pipeline_descriptor.multisample.count = 1;
    pipeline_descriptor.multisample.mask = 0xffffffff;
    pipeline_descriptor.fragment = *fragment;
    renderer.pipeline = gpu.wgpuDeviceCreateRenderPipeline(renderer.device, *pipeline_descriptor);
    offset_buffer_descriptor: WGPUBufferDescriptor = .{};
    offset_buffer_descriptor.size = size_of(V2f);
    offset_buffer_descriptor.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    renderer.offset_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *offset_buffer_descriptor);
    offset_layout := gpu.wgpuRenderPipelineGetBindGroupLayout(renderer.pipeline, 0);
    offset_entry: WGPUBindGroupEntry = .{};
    offset_entry.binding = 0;
    offset_entry.buffer = renderer.offset_buffer;
    offset_entry.size = size_of(V2f);
    offset_group_descriptor: WGPUBindGroupDescriptor = .{};
    offset_group_descriptor.layout = offset_layout;
    offset_group_descriptor.entryCount = 1;
    offset_group_descriptor.entries = *offset_entry;
    renderer.offset_bind_group = gpu.wgpuDeviceCreateBindGroup(renderer.device, *offset_group_descriptor);
    if platform.system.capture_rgba {
        renderer.capture_width = width;
        renderer.capture_height = height;
        renderer.capture_supported = true;
    }
    renderer.ready = true;
}

renderer_draw :: (renderer: *Renderer, platform: *Platform, offset: V2f) {
    if !renderer.ready return;
    gpu := *platform.gpu;
    surface_texture: WGPUSurfaceTexture = .{};
    gpu.wgpuSurfaceGetCurrentTexture(renderer.surface, *surface_texture);
    if surface_texture.status != .SuccessOptimal && surface_texture.status != .SuccessSuboptimal return;
    view := gpu.wgpuTextureCreateView(surface_texture.texture, null);
    attachment: WGPURenderPassColorAttachment = .{};
    attachment.view = view;
    attachment.loadOp = .Clear;
    attachment.storeOp = .Store;
    attachment.clearValue = .{ 0.035, 0.045, 0.075, 1.0 };
    pass_descriptor: WGPURenderPassDescriptor = .{};
    pass_descriptor.colorAttachmentCount = 1;
    pass_descriptor.colorAttachments = *attachment;
    gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.offset_buffer, 0, *offset, size_of(V2f));
    encoder := gpu.wgpuDeviceCreateCommandEncoder(renderer.device, null);
    pass := gpu.wgpuCommandEncoderBeginRenderPass(encoder, *pass_descriptor);
    gpu.wgpuRenderPassEncoderSetPipeline(pass, renderer.pipeline);
    gpu.wgpuRenderPassEncoderSetBindGroup(pass, 0, renderer.offset_bind_group, 0, null);
    gpu.wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
    gpu.wgpuRenderPassEncoderEnd(pass);
    command := gpu.wgpuCommandEncoderFinish(encoder, null);
    gpu.wgpuQueueSubmit(renderer.queue, 1, *command);
    gpu.wgpuSurfacePresent(renderer.surface);
    if renderer.capture_enabled {
        renderer_capture_frame(renderer, platform);
    }
}
