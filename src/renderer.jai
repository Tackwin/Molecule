#import "Basic";
#import "platform";
#import "Algebra";
#import "Store";

MAX_RENDER_INSTANCES :: 1024;
MAX_RENDER_GEOMETRY_VERTICES :: 4096;
MAX_RENDER_DRAW_BATCHES :: 16;

Render_Instance :: struct {
    model: M4f;
    color: V4f;
    vertex_offset: u32;
    padding0: u32;
    padding1: u32;
    padding2: u32;
}

Render_Camera :: struct {
    view_projection: M4f;
}

Render_Draw_Batch :: struct {
    vertex_offset: u32;
    vertex_count: u32;
    first_instance: u32;
    instance_count: u32;
}

Renderer :: struct {
    instance: WGPUInstance;
    adapter: WGPUAdapter;
    device: WGPUDevice;
    queue: WGPUQueue;
    surface: WGPUSurface;
    pipeline: WGPURenderPipeline;
    camera_buffer: WGPUBuffer;
    geometry_buffer: WGPUBuffer;
    instance_buffer: WGPUBuffer;
    depth_texture: WGPUTexture;
    depth_view: WGPUTextureView;
    depth_width: u32;
    depth_height: u32;
    bind_group: WGPUBindGroup;
    geometry_vertex_count: u32;
    instances: [..] Render_Instance;
    draw_batches: [..] Render_Draw_Batch;
    capture_width: u32;
    capture_height: u32;
    capture_supported: bool;
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

renderer_copy_rgba :: (renderer: *Renderer, platform: *Platform, rgba: [] u8) -> bool {
    if !renderer.capture_supported || !platform.system.capture_rgba {
        return false;
    }
    expected_byte_count := cast(int) renderer.capture_width * renderer.capture_height * 4;
    if rgba.count != expected_byte_count {
        return false;
    }
    return platform.system.capture_rgba(renderer.capture_width, renderer.capture_height, rgba);
}

renderer_unload :: (renderer: *Renderer, platform: *Platform) {
    gpu := *platform.gpu;
    if renderer.bind_group && gpu.wgpuBindGroupRelease {
        gpu.wgpuBindGroupRelease(renderer.bind_group);
    }
    if renderer.pipeline && gpu.wgpuRenderPipelineRelease {
        gpu.wgpuRenderPipelineRelease(renderer.pipeline);
    }
    if renderer.depth_view && gpu.wgpuTextureViewRelease {
        gpu.wgpuTextureViewRelease(renderer.depth_view);
    }
    if renderer.depth_texture && gpu.wgpuTextureRelease {
        gpu.wgpuTextureRelease(renderer.depth_texture);
    }
    if renderer.instance_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.instance_buffer);
    }
    if renderer.geometry_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.geometry_buffer);
    }
    if renderer.camera_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.camera_buffer);
    }
    if renderer.surface && gpu.wgpuSurfaceUnconfigure {
        gpu.wgpuSurfaceUnconfigure(renderer.surface);
    }
    if renderer.surface && gpu.wgpuSurfaceRelease {
        gpu.wgpuSurfaceRelease(renderer.surface);
    }
    if renderer.queue && gpu.wgpuQueueRelease {
        gpu.wgpuQueueRelease(renderer.queue);
    }
    if renderer.device && gpu.wgpuDeviceRelease {
        gpu.wgpuDeviceRelease(renderer.device);
    }
    if renderer.adapter && gpu.wgpuAdapterRelease {
        gpu.wgpuAdapterRelease(renderer.adapter);
    }
    if renderer.instance && gpu.wgpuInstanceRelease {
        gpu.wgpuInstanceRelease(renderer.instance);
    }
    array_free(renderer.instances);
    array_free(renderer.draw_batches);
    renderer.* = .{};
}

renderer_resize_depth_attachment :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32) {
    if width == 0 || height == 0 {
        return;
    }
    gpu := *platform.gpu;
    if renderer.depth_view && gpu.wgpuTextureViewRelease {
        gpu.wgpuTextureViewRelease(renderer.depth_view);
    }
    if renderer.depth_texture && gpu.wgpuTextureRelease {
        gpu.wgpuTextureRelease(renderer.depth_texture);
    }
    depth_descriptor: WGPUTextureDescriptor = .{};
    depth_descriptor.usage = WGPUTextureUsage_RenderAttachment;
    depth_descriptor.dimension = ._2D;
    depth_descriptor.size = .{ width, height, 1 };
    depth_descriptor.format = .Depth24Plus;
    depth_descriptor.mipLevelCount = 1;
    depth_descriptor.sampleCount = 1;
    renderer.depth_texture = gpu.wgpuDeviceCreateTexture(renderer.device, *depth_descriptor);
    renderer.depth_view = gpu.wgpuTextureCreateView(renderer.depth_texture, null);
    renderer.depth_width = width;
    renderer.depth_height = height;
}

renderer_init :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32, shader: *Shader_Asset) {
    if shader.asset.bytes.count == 0 {
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
    source.code = .{ data = shader.asset.bytes.data, length = xx shader.asset.bytes.count };
    shader_descriptor: WGPUShaderModuleDescriptor = .{};
    shader_descriptor.nextInChain = *source.chain;
    shader_module := gpu.wgpuDeviceCreateShaderModule(renderer.device, *shader_descriptor);

    target: WGPUColorTargetState = .{};
    target.format = .BGRA8Unorm;
    target.writeMask = WGPUColorWriteMask_All;
    fragment: WGPUFragmentState = .{};
    fragment.module = shader_module;
    fragment.entryPoint = to_wgpu_string("fs");
    fragment.targetCount = 1;
    fragment.targets = *target;
    pipeline_descriptor: WGPURenderPipelineDescriptor = .{};
    pipeline_descriptor.vertex.module = shader_module;
    pipeline_descriptor.vertex.entryPoint = to_wgpu_string("vs");
    pipeline_descriptor.primitive.topology = .TriangleList;
    depth_stencil: WGPUDepthStencilState = .{};
    depth_stencil.format = .Depth24Plus;
    depth_stencil.depthWriteEnabled = .True;
    depth_stencil.depthCompare = .Less;
    pipeline_descriptor.depthStencil = *depth_stencil;
    pipeline_descriptor.multisample.count = 1;
    pipeline_descriptor.multisample.mask = 0xffffffff;
    pipeline_descriptor.fragment = *fragment;
    renderer.pipeline = gpu.wgpuDeviceCreateRenderPipeline(renderer.device, *pipeline_descriptor);

    geometry_bytes := cast(u64) MAX_RENDER_GEOMETRY_VERTICES * size_of(Mesh_Vertex);
    geometry_descriptor: WGPUBufferDescriptor = .{};
    geometry_descriptor.size = geometry_bytes;
    geometry_descriptor.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    renderer.geometry_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *geometry_descriptor);

    camera_descriptor: WGPUBufferDescriptor = .{};
    camera_descriptor.size = size_of(Render_Camera);
    camera_descriptor.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    renderer.camera_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *camera_descriptor);
    instance_descriptor: WGPUBufferDescriptor = .{};
    instance_descriptor.size = MAX_RENDER_INSTANCES * size_of(Render_Instance);
    instance_descriptor.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    renderer.instance_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *instance_descriptor);
    renderer_resize_depth_attachment(renderer, platform, width, height);

    layout := gpu.wgpuRenderPipelineGetBindGroupLayout(renderer.pipeline, 0);
    entries: [3] WGPUBindGroupEntry;
    for 0..2 {
        entries[it] = .{};
    }
    entries[0].binding = 0;
    entries[0].buffer = renderer.camera_buffer;
    entries[0].size = size_of(Render_Camera);
    entries[1].binding = 1;
    entries[1].buffer = renderer.geometry_buffer;
    entries[1].size = geometry_bytes;
    entries[2].binding = 2;
    entries[2].buffer = renderer.instance_buffer;
    entries[2].size = MAX_RENDER_INSTANCES * size_of(Render_Instance);
    bind_group_descriptor: WGPUBindGroupDescriptor = .{};
    bind_group_descriptor.layout = layout;
    bind_group_descriptor.entryCount = entries.count;
    bind_group_descriptor.entries = *entries[0];
    renderer.bind_group = gpu.wgpuDeviceCreateBindGroup(renderer.device, *bind_group_descriptor);

    if platform.system.capture_rgba {
        renderer.capture_width = width;
        renderer.capture_height = height;
        renderer.capture_supported = true;
    }
    renderer.ready = true;
}

renderer_begin_instances :: (renderer: *Renderer) {
    renderer.instances.count = 0;
    renderer.draw_batches.count = 0;
}

renderer_upload_mesh_asset :: (renderer: *Renderer, platform: *Platform, mesh: *Mesh_Asset) -> bool {
    if !renderer.ready || mesh.vertices.count == 0 {
        return false;
    }
    if mesh.gpu_uploaded_asset_version == mesh.asset.version {
        return true;
    }
    if renderer.geometry_vertex_count + mesh.vertices.count > MAX_RENDER_GEOMETRY_VERTICES {
        return false;
    }
    mesh.gpu_vertex_offset = renderer.geometry_vertex_count;
    mesh.gpu_vertex_count = xx mesh.vertices.count;
    byte_offset := cast(u64) mesh.gpu_vertex_offset * size_of(Mesh_Vertex);
    byte_count := cast(u64) mesh.vertices.count * size_of(Mesh_Vertex);
    gpu := *platform.gpu;
    gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.geometry_buffer, byte_offset, mesh.vertices.data, byte_count);
    renderer.geometry_vertex_count += mesh.gpu_vertex_count;
    mesh.gpu_uploaded_asset_version = mesh.asset.version;
    return true;
}

renderer_push_mesh :: (renderer: *Renderer, mesh: Mesh_Asset, model: M4f, color: V4f) {
    if renderer.instances.count >= MAX_RENDER_INSTANCES return;
    if mesh.gpu_vertex_count == 0 return;
    if renderer.draw_batches.count == 0 ||
        renderer.draw_batches[renderer.draw_batches.count - 1].vertex_offset != mesh.gpu_vertex_offset {
        if renderer.draw_batches.count >= MAX_RENDER_DRAW_BATCHES return;
        array_add(*renderer.draw_batches, .{
            vertex_offset = mesh.gpu_vertex_offset,
            vertex_count = mesh.gpu_vertex_count,
            first_instance = xx renderer.instances.count,
        });
    }
    array_add(*renderer.instances, .{ model = model, color = color, vertex_offset = mesh.gpu_vertex_offset });
    renderer.draw_batches[renderer.draw_batches.count - 1].instance_count += 1;
}

renderer_draw :: (renderer: *Renderer, platform: *Platform, camera: Render_Camera, width: u32, height: u32) {
    if !renderer.ready || renderer.instances.count == 0 return;
    if renderer.depth_width != width || renderer.depth_height != height {
        renderer_resize_depth_attachment(renderer, platform, width, height);
    }
    gpu := *platform.gpu;
    gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.camera_buffer, 0, *camera, size_of(Render_Camera));
    gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.instance_buffer, 0, renderer.instances.data, cast(u64) renderer.instances.count * size_of(Render_Instance));
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
    depth_attachment: WGPURenderPassDepthStencilAttachment = .{};
    depth_attachment.view = renderer.depth_view;
    depth_attachment.depthLoadOp = .Clear;
    depth_attachment.depthStoreOp = .Store;
    depth_attachment.depthClearValue = 1.0;
    pass_descriptor.depthStencilAttachment = *depth_attachment;
    encoder := gpu.wgpuDeviceCreateCommandEncoder(renderer.device, null);
    pass := gpu.wgpuCommandEncoderBeginRenderPass(encoder, *pass_descriptor);
    gpu.wgpuRenderPassEncoderSetPipeline(pass, renderer.pipeline);
    gpu.wgpuRenderPassEncoderSetBindGroup(pass, 0, renderer.bind_group, 0, null);
    for renderer.draw_batches {
        gpu.wgpuRenderPassEncoderDraw(pass, it.vertex_count, it.instance_count, 0, it.first_instance);
    }
    gpu.wgpuRenderPassEncoderEnd(pass);
    command := gpu.wgpuCommandEncoderFinish(encoder, null);
    gpu.wgpuQueueSubmit(renderer.queue, 1, *command);
    gpu.wgpuSurfacePresent(renderer.surface);
}
