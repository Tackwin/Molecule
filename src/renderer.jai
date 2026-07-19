#import "Basic";
#import "platform";
#import "Algebra";
#import "Store";
#import "GUI";
#import "Qoi";

MAX_RENDER_INSTANCES :: 1024;
MAX_RENDER_GEOMETRY_VERTICES :: 4096;
MAX_RENDER_DRAW_BATCHES :: 16;
MAX_GUI_RENDER_INSTANCES :: GUI_MAX_QUADS;

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

Gui_Render_Uniform :: struct {
    framebuffer_size_pixels: V2f;
    padding: V2f;
}

Gui_Render_Instance :: struct {
    position_pixels: V2f;
    size_pixels: V2f;
    color: V4f;
    uv_rect: V4f;
    kind: u32;
    outline_width_pixels: float32;
    sort_z: float32;
    padding0: u32;
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
    gui_pipeline: WGPURenderPipeline;
    gui_uniform_buffer: WGPUBuffer;
    gui_instance_buffer: WGPUBuffer;
    gui_bind_group: WGPUBindGroup;
    gui_font_version: u32;
    geometry_shader_version: u32;
    geometry_shader_attempted_version: u32;
    gui_shader_version: u32;
    gui_shader_attempted_version: u32;
    geometry_vertex_count: u32;
    instances: [..] Render_Instance;
    draw_batches: [..] Render_Draw_Batch;
    gui_instances: [..] Gui_Render_Instance;
    capture_texture: WGPUTexture;
    capture_view: WGPUTextureView;
    capture_readback_buffer: WGPUBuffer;
    capture_rgba: [..] u8;
    capture_padded_bytes_per_row: u32;
    capture_width: u32;
    capture_height: u32;
    capture_ready: bool;
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

Renderer_Error_Scope_Result :: struct {
    done: bool;
    status: WGPUPopErrorScopeStatus;
    error_type: WGPUErrorType;
    message_count: u32;
    message: [0x400] u8;
}

renderer_error_scope_ready :: (
    status: WGPUPopErrorScopeStatus,
    error_type: WGPUErrorType,
    message: WGPUStringView,
    userdata1: *void,
    userdata2: *void
) #c_call {
    result := userdata1.(*Renderer_Error_Scope_Result);
    result.status = status;
    result.error_type = error_type;
    result.message_count = xx message.length;
    if result.message_count > result.message.count {
        result.message_count = xx result.message.count;
    }
    if result.message_count > 0 {
        memcpy(*result.message[0], message.data, result.message_count);
    }
    result.done = true;
}

renderer_push_validation_scope :: (renderer: *Renderer, platform: *Platform) -> bool {
    if !platform.gpu.wgpuDevicePushErrorScope || !platform.gpu.wgpuDevicePopErrorScope return false;
    platform.gpu.wgpuDevicePushErrorScope(renderer.device, .Validation);
    return true;
}

renderer_pop_validation_scope :: (
    renderer: *Renderer,
    platform: *Platform,
    label: string
) -> bool {
    result: Renderer_Error_Scope_Result;
    callback: WGPUPopErrorScopeCallbackInfo = .{};
    callback.mode = .AllowProcessEvents;
    callback.callback = renderer_error_scope_ready;
    callback.userdata1 = *result;
    platform.gpu.wgpuDevicePopErrorScope(renderer.device, callback);
    while !result.done {
        platform.gpu.wgpuInstanceProcessEvents(renderer.instance);
    }
    succeeded := result.status == .Success && result.error_type == .NoError;
    if !succeeded && platform.system.log {
        message: string = .{ data = *result.message[0], count = result.message_count };
        text := tprint("% failed: %", label, message);
        platform.system.log(.{ data = text.data, count = text.count });
    }
    return succeeded;
}

renderer_copy_rgba :: (renderer: *Renderer, platform: *Platform, rgba: [] u8) -> bool {
    if !renderer.capture_supported || !renderer.capture_ready {
        return false;
    }
    expected_byte_count := cast(int) renderer.capture_width * renderer.capture_height * 4;
    if rgba.count != expected_byte_count {
        return false;
    }
    memcpy(rgba.data, renderer.capture_rgba.data, rgba.count);
    renderer.capture_ready = false;
    return true;
}

Renderer_Capture_Map_State :: struct {
    done: bool;
    success: bool;
}

renderer_capture_map_ready :: (
    status: WGPUMapAsyncStatus,
    message: WGPUStringView,
    userdata1: *void,
    userdata2: *void
) #c_call {
    state := userdata1.(*Renderer_Capture_Map_State);
    state.success = status == .Success;
    state.done = true;
}

renderer_resize_capture_attachment :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32) {
    if width == 0 || height == 0 return;
    gpu := *platform.gpu;
    if renderer.capture_readback_buffer {
        gpu.wgpuBufferRelease(renderer.capture_readback_buffer);
    }
    if renderer.capture_view {
        gpu.wgpuTextureViewRelease(renderer.capture_view);
    }
    if renderer.capture_texture {
        gpu.wgpuTextureRelease(renderer.capture_texture);
    }
    texture_descriptor: WGPUTextureDescriptor = .{};
    texture_descriptor.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc;
    texture_descriptor.dimension = ._2D;
    texture_descriptor.size = .{ width, height, 1 };
    texture_descriptor.format = .BGRA8Unorm;
    texture_descriptor.mipLevelCount = 1;
    texture_descriptor.sampleCount = 1;
    renderer.capture_texture = gpu.wgpuDeviceCreateTexture(renderer.device, *texture_descriptor);
    renderer.capture_view = gpu.wgpuTextureCreateView(renderer.capture_texture, null);
    unpadded_bytes_per_row := width * 4;
    renderer.capture_padded_bytes_per_row = (unpadded_bytes_per_row + 255) & ~cast(u32) 255;
    readback_descriptor: WGPUBufferDescriptor = .{};
    readback_descriptor.size = cast(u64) renderer.capture_padded_bytes_per_row * height;
    readback_descriptor.usage = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead;
    renderer.capture_readback_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *readback_descriptor);
    renderer.capture_width = width;
    renderer.capture_height = height;
    renderer.capture_ready = false;
}

renderer_finish_capture :: (renderer: *Renderer, platform: *Platform) -> bool {
    gpu := *platform.gpu;
    mapped_byte_count := cast(u64) renderer.capture_padded_bytes_per_row * renderer.capture_height;
    map_state: Renderer_Capture_Map_State;
    callback_info: WGPUBufferMapCallbackInfo = .{};
    callback_info.mode = .AllowProcessEvents;
    callback_info.callback = renderer_capture_map_ready;
    callback_info.userdata1 = *map_state;
    gpu.wgpuBufferMapAsync(
        renderer.capture_readback_buffer,
        WGPUMapMode_Read,
        0,
        mapped_byte_count,
        callback_info
    );
    while !map_state.done {
        gpu.wgpuInstanceProcessEvents(renderer.instance);
    }
    if !map_state.success return false;
    mapped := gpu.wgpuBufferGetConstMappedRange(renderer.capture_readback_buffer, 0, mapped_byte_count).(*u8);
    if !mapped {
        gpu.wgpuBufferUnmap(renderer.capture_readback_buffer);
        return false;
    }
    array_resize(*renderer.capture_rgba, cast(int) renderer.capture_width * renderer.capture_height * 4);
    for y: 0..renderer.capture_height - 1 {
        source_row := mapped + cast(u64) y * renderer.capture_padded_bytes_per_row;
        destination_row := renderer.capture_rgba.data + cast(u64) y * renderer.capture_width * 4;
        for x: 0..renderer.capture_width - 1 {
            source := source_row + cast(u64) x * 4;
            destination := destination_row + cast(u64) x * 4;
            destination[0] = source[2];
            destination[1] = source[1];
            destination[2] = source[0];
            destination[3] = source[3];
        }
    }
    gpu.wgpuBufferUnmap(renderer.capture_readback_buffer);
    renderer.capture_ready = true;
    return true;
}

renderer_unload :: (renderer: *Renderer, platform: *Platform) {
    gpu := *platform.gpu;
    if renderer.bind_group && gpu.wgpuBindGroupRelease {
        gpu.wgpuBindGroupRelease(renderer.bind_group);
    }
    if renderer.pipeline && gpu.wgpuRenderPipelineRelease {
        gpu.wgpuRenderPipelineRelease(renderer.pipeline);
    }
    if renderer.gui_bind_group && gpu.wgpuBindGroupRelease {
        gpu.wgpuBindGroupRelease(renderer.gui_bind_group);
    }
    if renderer.gui_pipeline && gpu.wgpuRenderPipelineRelease {
        gpu.wgpuRenderPipelineRelease(renderer.gui_pipeline);
    }
    if renderer.depth_view && gpu.wgpuTextureViewRelease {
        gpu.wgpuTextureViewRelease(renderer.depth_view);
    }
    if renderer.depth_texture && gpu.wgpuTextureRelease {
        gpu.wgpuTextureRelease(renderer.depth_texture);
    }
    if renderer.capture_readback_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.capture_readback_buffer);
    }
    if renderer.capture_view && gpu.wgpuTextureViewRelease {
        gpu.wgpuTextureViewRelease(renderer.capture_view);
    }
    if renderer.capture_texture && gpu.wgpuTextureRelease {
        gpu.wgpuTextureRelease(renderer.capture_texture);
    }
    if renderer.instance_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.instance_buffer);
    }
    if renderer.gui_instance_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.gui_instance_buffer);
    }
    if renderer.gui_uniform_buffer && gpu.wgpuBufferRelease {
        gpu.wgpuBufferRelease(renderer.gui_uniform_buffer);
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
    array_free(renderer.gui_instances);
    array_free(renderer.capture_rgba);
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

renderer_create_geometry_pipeline :: (
    renderer: *Renderer,
    platform: *Platform,
    shader: *Shader_Asset
) -> WGPURenderPipeline {
    if shader.asset.bytes.count == 0 return null;
    gpu := *platform.gpu;
    source: WGPUShaderSourceWGSL = .{};
    source.chain.sType = .ShaderSourceWGSL;
    source.code = .{
        data = shader.asset.bytes.data,
        length = xx shader.asset.bytes.count,
    };
    shader_descriptor: WGPUShaderModuleDescriptor = .{};
    shader_descriptor.nextInChain = *source.chain;
    module_scope := renderer_push_validation_scope(renderer, platform);
    shader_module := gpu.wgpuDeviceCreateShaderModule(renderer.device, *shader_descriptor);
    module_valid := shader_module != null;
    if module_scope {
        module_valid = renderer_pop_validation_scope(renderer, platform, "geometry shader module") && module_valid;
    }
    if !module_valid {
        if shader_module && gpu.wgpuShaderModuleRelease {
            gpu.wgpuShaderModuleRelease(shader_module);
        }
        return null;
    }
    target: WGPUColorTargetState = .{};
    target.format = .BGRA8Unorm;
    target.writeMask = WGPUColorWriteMask_All;
    fragment: WGPUFragmentState = .{};
    fragment.module = shader_module;
    fragment.entryPoint = to_wgpu_string("fs");
    fragment.targetCount = 1;
    fragment.targets = *target;
    descriptor: WGPURenderPipelineDescriptor = .{};
    descriptor.vertex.module = shader_module;
    descriptor.vertex.entryPoint = to_wgpu_string("vs");
    descriptor.primitive.topology = .TriangleList;
    depth_stencil: WGPUDepthStencilState = .{};
    depth_stencil.format = .Depth24Plus;
    depth_stencil.depthWriteEnabled = .True;
    depth_stencil.depthCompare = .Less;
    descriptor.depthStencil = *depth_stencil;
    descriptor.multisample.count = 1;
    descriptor.multisample.mask = 0xffffffff;
    descriptor.fragment = *fragment;
    pipeline_scope := renderer_push_validation_scope(renderer, platform);
    pipeline := gpu.wgpuDeviceCreateRenderPipeline(renderer.device, *descriptor);
    pipeline_valid := pipeline != null;
    if pipeline_scope {
        pipeline_valid = renderer_pop_validation_scope(renderer, platform, "geometry shader pipeline") && pipeline_valid;
    }
    if gpu.wgpuShaderModuleRelease {
        gpu.wgpuShaderModuleRelease(shader_module);
    }
    if !pipeline_valid {
        if pipeline && gpu.wgpuRenderPipelineRelease {
            gpu.wgpuRenderPipelineRelease(pipeline);
        }
        return null;
    }
    return pipeline;
}

renderer_create_gui_pipeline :: (
    renderer: *Renderer,
    platform: *Platform,
    shader: *Shader_Asset
) -> WGPURenderPipeline {
    if shader.asset.bytes.count == 0 return null;
    gpu := *platform.gpu;
    source: WGPUShaderSourceWGSL = .{};
    source.chain.sType = .ShaderSourceWGSL;
    source.code = .{
        data = shader.asset.bytes.data,
        length = xx shader.asset.bytes.count,
    };
    shader_descriptor: WGPUShaderModuleDescriptor = .{};
    shader_descriptor.nextInChain = *source.chain;
    module_scope := renderer_push_validation_scope(renderer, platform);
    shader_module := gpu.wgpuDeviceCreateShaderModule(renderer.device, *shader_descriptor);
    module_valid := shader_module != null;
    if module_scope {
        module_valid = renderer_pop_validation_scope(renderer, platform, "gui shader module") && module_valid;
    }
    if !module_valid {
        if shader_module && gpu.wgpuShaderModuleRelease {
            gpu.wgpuShaderModuleRelease(shader_module);
        }
        return null;
    }
    blend: WGPUBlendState = .{};
    blend.color = .{ operation = .Add, srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha };
    blend.alpha = .{ operation = .Add, srcFactor = .One, dstFactor = .OneMinusSrcAlpha };
    target: WGPUColorTargetState = .{};
    target.format = .BGRA8Unorm;
    target.blend = *blend;
    target.writeMask = WGPUColorWriteMask_All;
    fragment: WGPUFragmentState = .{};
    fragment.module = shader_module;
    fragment.entryPoint = to_wgpu_string("fs");
    fragment.targetCount = 1;
    fragment.targets = *target;
    descriptor: WGPURenderPipelineDescriptor = .{};
    descriptor.vertex.module = shader_module;
    descriptor.vertex.entryPoint = to_wgpu_string("vs");
    descriptor.primitive.topology = .TriangleList;
    descriptor.multisample.count = 1;
    descriptor.multisample.mask = 0xffffffff;
    descriptor.fragment = *fragment;
    pipeline_scope := renderer_push_validation_scope(renderer, platform);
    pipeline := gpu.wgpuDeviceCreateRenderPipeline(renderer.device, *descriptor);
    pipeline_valid := pipeline != null;
    if pipeline_scope {
        pipeline_valid = renderer_pop_validation_scope(renderer, platform, "gui shader pipeline") && pipeline_valid;
    }
    if gpu.wgpuShaderModuleRelease {
        gpu.wgpuShaderModuleRelease(shader_module);
    }
    if !pipeline_valid {
        if pipeline && gpu.wgpuRenderPipelineRelease {
            gpu.wgpuRenderPipelineRelease(pipeline);
        }
        return null;
    }
    return pipeline;
}

renderer_create_geometry_bind_group :: (
    renderer: *Renderer,
    platform: *Platform,
    pipeline: WGPURenderPipeline
) -> WGPUBindGroup {
    if !pipeline || !renderer.camera_buffer || !renderer.geometry_buffer || !renderer.instance_buffer return null;
    gpu := *platform.gpu;
    geometry_bytes := cast(u64) MAX_RENDER_GEOMETRY_VERTICES * size_of(Mesh_Vertex);
    layout := gpu.wgpuRenderPipelineGetBindGroupLayout(pipeline, 0);
    entries: [3] WGPUBindGroupEntry;
    for 0..entries.count - 1 {
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
    descriptor: WGPUBindGroupDescriptor = .{};
    descriptor.layout = layout;
    descriptor.entryCount = entries.count;
    descriptor.entries = *entries[0];
    bind_group := gpu.wgpuDeviceCreateBindGroup(renderer.device, *descriptor);
    if gpu.wgpuBindGroupLayoutRelease {
        gpu.wgpuBindGroupLayoutRelease(layout);
    }
    return bind_group;
}

renderer_create_gui_bind_group :: (
    renderer: *Renderer,
    platform: *Platform,
    pipeline: WGPURenderPipeline,
    texture: *Texture_Asset
) -> WGPUBindGroup {
    if !pipeline || !texture.gpu_view || !texture.gpu_sampler return null;
    gpu := *platform.gpu;
    layout := gpu.wgpuRenderPipelineGetBindGroupLayout(pipeline, 0);
    entries: [4] WGPUBindGroupEntry;
    for 0..entries.count - 1 {
        entries[it] = .{};
    }
    entries[0].binding = 0;
    entries[0].buffer = renderer.gui_uniform_buffer;
    entries[0].size = size_of(Gui_Render_Uniform);
    entries[1].binding = 1;
    entries[1].buffer = renderer.gui_instance_buffer;
    entries[1].size = MAX_GUI_RENDER_INSTANCES * size_of(Gui_Render_Instance);
    entries[2].binding = 2;
    entries[2].textureView = texture.gpu_view;
    entries[3].binding = 3;
    entries[3].sampler = texture.gpu_sampler;
    descriptor: WGPUBindGroupDescriptor = .{};
    descriptor.layout = layout;
    descriptor.entryCount = entries.count;
    descriptor.entries = *entries[0];
    bind_group := gpu.wgpuDeviceCreateBindGroup(renderer.device, *descriptor);
    if gpu.wgpuBindGroupLayoutRelease {
        gpu.wgpuBindGroupLayoutRelease(layout);
    }
    return bind_group;
}

renderer_init :: (renderer: *Renderer, platform: *Platform, width: u32, height: u32, store: *Store) {
    if store.geometry_shader.asset.bytes.count == 0 || store.gui_shader.asset.bytes.count == 0 {
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

    renderer.pipeline = renderer_create_geometry_pipeline(renderer, platform, *store.geometry_shader);
    renderer.gui_pipeline = renderer_create_gui_pipeline(renderer, platform, *store.gui_shader);
    if !renderer.pipeline || !renderer.gui_pipeline return;

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
    gui_uniform_descriptor: WGPUBufferDescriptor = .{};
    gui_uniform_descriptor.size = size_of(Gui_Render_Uniform);
    gui_uniform_descriptor.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
    renderer.gui_uniform_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *gui_uniform_descriptor);
    gui_instance_descriptor: WGPUBufferDescriptor = .{};
    gui_instance_descriptor.size = MAX_GUI_RENDER_INSTANCES * size_of(Gui_Render_Instance);
    gui_instance_descriptor.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst;
    renderer.gui_instance_buffer = gpu.wgpuDeviceCreateBuffer(renderer.device, *gui_instance_descriptor);
    renderer_resize_depth_attachment(renderer, platform, width, height);

    renderer.bind_group = renderer_create_geometry_bind_group(renderer, platform, renderer.pipeline);
    if !renderer.bind_group return;

    renderer.capture_supported = gpu.wgpuCommandEncoderCopyTextureToBuffer &&
        gpu.wgpuBufferMapAsync && gpu.wgpuBufferGetConstMappedRange && gpu.wgpuBufferUnmap;
    if renderer.capture_supported {
        renderer_resize_capture_attachment(renderer, platform, width, height);
    }
    renderer.geometry_shader_version = store.geometry_shader.asset.version;
    renderer.geometry_shader_attempted_version = store.geometry_shader.asset.version;
    renderer.gui_shader_version = store.gui_shader.asset.version;
    renderer.gui_shader_attempted_version = store.gui_shader.asset.version;
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

renderer_upload_texture_asset :: (renderer: *Renderer, platform: *Platform, texture: *Texture_Asset) -> bool {
    if !renderer.ready || texture.pixels.count == 0 return false;
    if texture.gpu_uploaded_asset_version == texture.asset.version return true;
    if texture.width * 4 % 256 != 0 return false;
    gpu := *platform.gpu;
    descriptor: WGPUTextureDescriptor = .{};
    descriptor.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst;
    descriptor.dimension = ._2D;
    descriptor.size = .{ texture.width, texture.height, 1 };
    descriptor.format = .RGBA8Unorm;
    descriptor.mipLevelCount = 1;
    descriptor.sampleCount = 1;
    texture.gpu_texture = gpu.wgpuDeviceCreateTexture(renderer.device, *descriptor);
    texture.gpu_view = gpu.wgpuTextureCreateView(texture.gpu_texture, null);
    sampler_descriptor: WGPUSamplerDescriptor = .{};
    sampler_descriptor.addressModeU = .ClampToEdge;
    sampler_descriptor.addressModeV = .ClampToEdge;
    sampler_descriptor.addressModeW = .ClampToEdge;
    sampler_descriptor.magFilter = .Linear;
    sampler_descriptor.minFilter = .Linear;
    sampler_descriptor.mipmapFilter = .Nearest;
    sampler_descriptor.lodMaxClamp = 32;
    sampler_descriptor.maxAnisotropy = 1;
    texture.gpu_sampler = gpu.wgpuDeviceCreateSampler(renderer.device, *sampler_descriptor);
    destination: WGPUTexelCopyTextureInfo = .{};
    destination.texture = texture.gpu_texture;
    destination.aspect = .All;
    layout: WGPUTexelCopyBufferLayout = .{};
    layout.bytesPerRow = texture.width * 4;
    layout.rowsPerImage = texture.height;
    extent: WGPUExtent3D = .{ texture.width, texture.height, 1 };
    gpu.wgpuQueueWriteTexture(renderer.queue, *destination, texture.pixels.data, cast(u64) texture.pixels.count * size_of(Qoi_Pixel), *layout, *extent);
    new_bind_group := renderer_create_gui_bind_group(renderer, platform, renderer.gui_pipeline, texture);
    if !new_bind_group return false;
    if renderer.gui_bind_group && gpu.wgpuBindGroupRelease {
        gpu.wgpuBindGroupRelease(renderer.gui_bind_group);
    }
    renderer.gui_bind_group = new_bind_group;
    texture.gpu_uploaded_asset_version = texture.asset.version;
    return renderer.gui_bind_group != null;
}

renderer_reload_geometry_shader :: (
    renderer: *Renderer,
    platform: *Platform,
    shader: *Shader_Asset
) -> bool {
    renderer.geometry_shader_attempted_version = shader.asset.version;
    new_pipeline := renderer_create_geometry_pipeline(renderer, platform, shader);
    if !new_pipeline return false;
    new_bind_group := renderer_create_geometry_bind_group(renderer, platform, new_pipeline);
    if !new_bind_group {
        if platform.gpu.wgpuRenderPipelineRelease {
            platform.gpu.wgpuRenderPipelineRelease(new_pipeline);
        }
        return false;
    }
    old_pipeline := renderer.pipeline;
    old_bind_group := renderer.bind_group;
    renderer.pipeline = new_pipeline;
    renderer.bind_group = new_bind_group;
    renderer.geometry_shader_version = shader.asset.version;
    if platform.system.log {
        message := tprint("geometry shader pipeline reloaded, version %", shader.asset.version);
        platform.system.log(.{ data = message.data, count = message.count });
    }
    if old_bind_group && platform.gpu.wgpuBindGroupRelease {
        platform.gpu.wgpuBindGroupRelease(old_bind_group);
    }
    if old_pipeline && platform.gpu.wgpuRenderPipelineRelease {
        platform.gpu.wgpuRenderPipelineRelease(old_pipeline);
    }
    return true;
}

renderer_reload_gui_shader :: (
    renderer: *Renderer,
    platform: *Platform,
    shader: *Shader_Asset,
    font_atlas: *Texture_Asset
) -> bool {
    renderer.gui_shader_attempted_version = shader.asset.version;
    new_pipeline := renderer_create_gui_pipeline(renderer, platform, shader);
    if !new_pipeline return false;
    new_bind_group := renderer_create_gui_bind_group(renderer, platform, new_pipeline, font_atlas);
    if !new_bind_group {
        if platform.gpu.wgpuRenderPipelineRelease {
            platform.gpu.wgpuRenderPipelineRelease(new_pipeline);
        }
        return false;
    }
    old_pipeline := renderer.gui_pipeline;
    old_bind_group := renderer.gui_bind_group;
    renderer.gui_pipeline = new_pipeline;
    renderer.gui_bind_group = new_bind_group;
    renderer.gui_shader_version = shader.asset.version;
    if platform.system.log {
        message := tprint("gui shader pipeline reloaded, version %", shader.asset.version);
        platform.system.log(.{ data = message.data, count = message.count });
    }
    if old_bind_group && platform.gpu.wgpuBindGroupRelease {
        platform.gpu.wgpuBindGroupRelease(old_bind_group);
    }
    if old_pipeline && platform.gpu.wgpuRenderPipelineRelease {
        platform.gpu.wgpuRenderPipelineRelease(old_pipeline);
    }
    return true;
}

renderer_reload_changed_shaders :: (renderer: *Renderer, platform: *Platform, store: *Store) {
    if !renderer.ready return;
    geometry_version := store.geometry_shader.asset.version;
    if geometry_version != renderer.geometry_shader_attempted_version {
        renderer_reload_geometry_shader(renderer, platform, *store.geometry_shader);
    }
    gui_version := store.gui_shader.asset.version;
    if gui_version != renderer.gui_shader_attempted_version {
        renderer_reload_gui_shader(renderer, platform, *store.gui_shader, *store.verdana_font.atlas);
    }
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

renderer_push_sorted_gui_instance :: (renderer: *Renderer, quad: Gui_Quad) {
    if renderer.gui_instances.count >= MAX_GUI_RENDER_INSTANCES return;
    instance: Gui_Render_Instance = .{};
    instance.position_pixels = quad.position_pixels;
    instance.size_pixels = quad.size_pixels;
    instance.color = quad.color;
    instance.uv_rect = quad.uv_rect;
    instance.kind = cast(u32) quad.kind;
    instance.outline_width_pixels = quad.outline_width_pixels;
    instance.sort_z = quad.z;
    array_add(*renderer.gui_instances, instance);
    cursor := renderer.gui_instances.count - 1;
    while cursor > 0 && renderer.gui_instances[cursor - 1].sort_z > quad.z {
        renderer.gui_instances[cursor] = renderer.gui_instances[cursor - 1];
        cursor -= 1;
    }
    renderer.gui_instances[cursor] = instance;
}

renderer_build_gui_instances :: (renderer: *Renderer, gui: *GUI_State) {
    renderer.gui_instances.count = 0;
    for opaque_pass: 0..1 {
        for gui.quads {
            opaque := it.kind == .Solid && it.color.w >= 1.0 && it.outline_width_pixels == 0;
            if opaque_pass == 0 && !opaque continue;
            if opaque_pass == 1 && opaque continue;
            renderer_push_sorted_gui_instance(renderer, it);
        }
    }
}

renderer_draw :: (
    renderer: *Renderer,
    platform: *Platform,
    camera: Render_Camera,
    gui: *GUI_State,
    width: u32,
    height: u32,
    capture_frame: bool
) {
    if !renderer.ready return;
    if renderer.depth_width != width || renderer.depth_height != height {
        renderer_resize_depth_attachment(renderer, platform, width, height);
    }
    if renderer.capture_supported && (renderer.capture_width != width || renderer.capture_height != height) {
        renderer_resize_capture_attachment(renderer, platform, width, height);
    }
    renderer_build_gui_instances(renderer, gui);
    gpu := *platform.gpu;
    if renderer.instances.count > 0 {
        gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.camera_buffer, 0, *camera, size_of(Render_Camera));
        gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.instance_buffer, 0, renderer.instances.data, cast(u64) renderer.instances.count * size_of(Render_Instance));
    }
    if renderer.gui_instances.count > 0 && renderer.gui_bind_group {
        gui_uniform: Gui_Render_Uniform = .{ framebuffer_size_pixels = .{ cast(float32) width, cast(float32) height } };
        gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.gui_uniform_buffer, 0, *gui_uniform, size_of(Gui_Render_Uniform));
        gpu.wgpuQueueWriteBuffer(renderer.queue, renderer.gui_instance_buffer, 0, renderer.gui_instances.data, cast(u64) renderer.gui_instances.count * size_of(Gui_Render_Instance));
    }
    surface_texture: WGPUSurfaceTexture = .{};
    view: WGPUTextureView;
    if capture_frame && renderer.capture_supported {
        view = renderer.capture_view;
    } else {
        gpu.wgpuSurfaceGetCurrentTexture(renderer.surface, *surface_texture);
        if surface_texture.status != .SuccessOptimal && surface_texture.status != .SuccessSuboptimal return;
        view = gpu.wgpuTextureCreateView(surface_texture.texture, null);
    }
    attachment: WGPURenderPassColorAttachment = .{};
    attachment.view = view;
    attachment.loadOp = .Clear;
    attachment.storeOp = .Store;
    attachment.clearValue = .{ 0.035, 0.045, 0.075, 1.0 };
    pass_descriptor: WGPURenderPassDescriptor = .{};
    pass_descriptor.colorAttachmentCount = 1;
    pass_descriptor.colorAttachments = *attachment;
    encoder := gpu.wgpuDeviceCreateCommandEncoder(renderer.device, null);
    if renderer.instances.count > 0 {
        depth_attachment: WGPURenderPassDepthStencilAttachment = .{};
        depth_attachment.view = renderer.depth_view;
        depth_attachment.depthLoadOp = .Clear;
        depth_attachment.depthStoreOp = .Store;
        depth_attachment.depthClearValue = 1.0;
        pass_descriptor.depthStencilAttachment = *depth_attachment;
        pass := gpu.wgpuCommandEncoderBeginRenderPass(encoder, *pass_descriptor);
        gpu.wgpuRenderPassEncoderSetPipeline(pass, renderer.pipeline);
        gpu.wgpuRenderPassEncoderSetBindGroup(pass, 0, renderer.bind_group, 0, null);
        for renderer.draw_batches {
            gpu.wgpuRenderPassEncoderDraw(pass, it.vertex_count, it.instance_count, 0, it.first_instance);
        }
        gpu.wgpuRenderPassEncoderEnd(pass);
    }
    if renderer.gui_instances.count > 0 && renderer.gui_bind_group {
        attachment.loadOp = ifx renderer.instances.count > 0 then .Load else .Clear;
        pass_descriptor.depthStencilAttachment = null;
        gui_pass := gpu.wgpuCommandEncoderBeginRenderPass(encoder, *pass_descriptor);
        gpu.wgpuRenderPassEncoderSetPipeline(gui_pass, renderer.gui_pipeline);
        gpu.wgpuRenderPassEncoderSetBindGroup(gui_pass, 0, renderer.gui_bind_group, 0, null);
        gpu.wgpuRenderPassEncoderDraw(gui_pass, 6, cast(u32) renderer.gui_instances.count, 0, 0);
        gpu.wgpuRenderPassEncoderEnd(gui_pass);
    }
    if capture_frame && renderer.capture_supported {
        source: WGPUTexelCopyTextureInfo = .{};
        source.texture = renderer.capture_texture;
        source.aspect = .All;
        destination: WGPUTexelCopyBufferInfo = .{};
        destination.buffer = renderer.capture_readback_buffer;
        destination.layout.bytesPerRow = renderer.capture_padded_bytes_per_row;
        destination.layout.rowsPerImage = height;
        extent: WGPUExtent3D = .{ width, height, 1 };
        gpu.wgpuCommandEncoderCopyTextureToBuffer(encoder, *source, *destination, *extent);
    }
    command := gpu.wgpuCommandEncoderFinish(encoder, null);
    gpu.wgpuQueueSubmit(renderer.queue, 1, *command);
    if capture_frame && renderer.capture_supported {
        renderer_finish_capture(renderer, platform);
    } else {
        gpu.wgpuSurfacePresent(renderer.surface);
        gpu.wgpuTextureViewRelease(view);
    }
}
