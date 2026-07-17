#import "platform";
#import "Algebra";

Renderer :: struct {
    instance: WGPUInstance;
    adapter: WGPUAdapter;
    device: WGPUDevice;
    queue: WGPUQueue;
    surface: WGPUSurface;
    pipeline: WGPURenderPipeline;
    offset_buffer: WGPUBuffer;
    offset_bind_group: WGPUBindGroup;
    ready: bool;
}

triangle_wgsl: string = "struct O { @builtin(position) p: vec4f, @location(0) c: vec3f, } @group(0) @binding(0) var<uniform> offset: vec2f; @vertex fn vs(@builtin(vertex_index) i: u32) -> O { let p = array<vec2f, 3>(vec2f(0.0, 0.65), vec2f(-0.65, -0.65), vec2f(0.65, -0.65)); let c = array<vec3f, 3>(vec3f(1.0, 0.25, 0.2), vec3f(0.2, 1.0, 0.45), vec3f(0.25, 0.55, 1.0)); var o: O; o.p = vec4f(p[i] + offset, 0.0, 1.0); o.c = c[i]; return o; } @fragment fn fs(i: O) -> @location(0) vec4f { return vec4f(i.c, 1.0); }";

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

renderer_init :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32) {
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
    source.code = to_wgpu_string(triangle_wgsl);
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
}
