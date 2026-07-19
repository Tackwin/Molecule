#import "Basic";
#import "String";
#import "Pool";
#import "platform";
#import "Algebra";
#import "Qoi";

Asset_Load_State :: enum u8 {
    UNLOADED;
    READY;
    FAILED;
}

Store_Asset :: struct {
    path: string;
    bytes: [] u8;
    state: Asset_Load_State;
    version: u32;
    request: Asset_Request_Handle;
}

Mesh_Vertex :: struct {
    position: V3f;
    position_padding: float32;
    normal: V3f;
    normal_padding: float32;
}

Mesh_Asset :: struct {
    asset: Store_Asset;
    vertices: [..] Mesh_Vertex;
    gpu_vertex_offset: u32;
    gpu_vertex_count: u32;
    gpu_uploaded_asset_version: u32;
}

Shader_Asset :: struct {
    asset: Store_Asset;
}

Texture_Asset :: struct {
    asset: Store_Asset;
    width: u32;
    height: u32;
    pixels: [..] Qoi_Pixel;
    gpu_texture: WGPUTexture;
    gpu_view: WGPUTextureView;
    gpu_sampler: WGPUSampler;
    gpu_uploaded_asset_version: u32;
}

Font_Glyph :: struct {
    advance: float32;
    plane_x: float32;
    plane_y: float32;
    plane_width: float32;
    plane_height: float32;
    uv_rect: V4f;
}

Font_Asset :: struct {
    metrics_asset: Store_Asset;
    atlas: Texture_Asset;
    glyphs: [256] Font_Glyph;
}

Store :: struct {
    pool: Pool;
    pool_allocator_proc: Allocator_Proc;
    shader_watch: File_Watch_Handle;
    geometry_shader: Shader_Asset;
    gui_shader: Shader_Asset;
    cube_mesh: Mesh_Asset;
    sphere_mesh: Mesh_Asset;
    verdana_font: Font_Asset;
}

Allocator_Proc_Bits :: union {
    proc: Allocator_Proc;
    bits: u64;
}

store_promote_qoi_texture :: (texture: *Texture_Asset, store: *Store, platform: *Platform) {
    if texture.asset.bytes.count == 0 || texture.pixels.count > 0 return;
    if texture.asset.bytes.count < 14 {
        texture.asset.state = .FAILED;
        return;
    }
    width := cast(u32) texture.asset.bytes[4] * 0x01000000 + cast(u32) texture.asset.bytes[5] * 0x00010000 +
        cast(u32) texture.asset.bytes[6] * 0x00000100 + cast(u32) texture.asset.bytes[7];
    height := cast(u32) texture.asset.bytes[8] * 0x01000000 + cast(u32) texture.asset.bytes[9] * 0x00010000 +
        cast(u32) texture.asset.bytes[10] * 0x00000100 + cast(u32) texture.asset.bytes[11];
    if platform.system.log {
        store_allocator: Allocator_Proc_Bits;
        store_allocator.proc = store.pool_allocator_proc;
        platform_allocator: Allocator_Proc_Bits;
        platform_allocator.proc = platform.system.persistent_pool_allocator_proc;
        message := tprint(
            "QOI atlas dimensions: %x%, store allocator null=% platform allocator null=% store_proc=% platform_proc=%",
            width,
            height,
            !store.pool_allocator_proc,
            !platform.system.persistent_pool_allocator_proc,
            store_allocator.bits,
            platform_allocator.bits
        );
        platform.system.log(.{ data = message.data, count = message.count });
    }
    texture.pixels.allocator = .{ store.pool_allocator_proc, *store.pool };
    array_resize(*texture.pixels, cast(int) width * height);
    if platform.system.log {
        message := "QOI atlas pixels allocated";
        platform.system.log(.{ data = message.data, count = message.count });
    }
    info, decoded := qoi_decode(texture.asset.bytes, texture.pixels);
    if platform.system.log {
        message := "QOI atlas decode returned";
        platform.system.log(.{ data = message.data, count = message.count });
    }
    if !decoded {
        texture.asset.state = .FAILED;
        return;
    }
    texture.width = info.width;
    texture.height = info.height;
}

store_promote_font_metrics :: (font: *Font_Asset, store: *Store) {
    if font.metrics_asset.bytes.count == 0 return;
    if font.atlas.width == 0 || font.atlas.height == 0 return;
    if font.glyphs[65].advance != 0 return;
    text: string = .{ data = font.metrics_asset.bytes.data, count = font.metrics_asset.bytes.count };
    while text.count > 0 {
        line := store_next_line(*text);
        line = trim(line, " \t\r\n");
        if line.count == 0 continue;
        unicode: s32;
        glyph: Font_Glyph;
        atlas_x: float32;
        atlas_y: float32;
        atlas_width: float32;
        atlas_height: float32;
        if !scan2(line, "%,%,%,%,%,%,%,%,%,%", *unicode, *glyph.advance, *glyph.plane_x, *glyph.plane_y,
            *glyph.plane_width, *glyph.plane_height, *atlas_x, *atlas_y, *atlas_width, *atlas_height) continue;
        if unicode < 0 || unicode >= font.glyphs.count continue;
        atlas_pixel_width := cast(float32) font.atlas.width;
        atlas_pixel_height := cast(float32) font.atlas.height;
        glyph.uv_rect = .{
            atlas_x / atlas_pixel_width,
            (atlas_pixel_height - atlas_height) / atlas_pixel_height,
            (atlas_width - atlas_x) / atlas_pixel_width,
            (atlas_height - atlas_y) / atlas_pixel_height,
        };
        font.glyphs[unicode] = glyph;
    }
}

store_next_line :: (text: *string) -> string {
    result := text.*;
    while text.count > 0 && text.data[0] != #char "\n" {
        text.data += 1;
        text.count -= 1;
    }
    result.count -= text.count;
    if text.count > 0 {
        text.data += 1;
        text.count -= 1;
    }
    return result;
}

store_promote_obj_mesh :: (mesh: *Mesh_Asset, store: *Store) {
    if mesh.asset.bytes.count == 0 || mesh.vertices.count > 0 return;
    mesh.vertices.allocator = .{ store.pool_allocator_proc, *store.pool };
    text: string = .{ data = mesh.asset.bytes.data, count = mesh.asset.bytes.count };
    positions: [256] V3f;
    position_count: s32 = 0;
    while text.count > 0 {
        line := store_next_line(*text);
        if line.count < 2 continue;
        if line.data[0] == #char "v" && line.data[1] == #char " " {
            position: V3f;
            if !scan2(line, "v % % %", *position.x, *position.y, *position.z) {
                mesh.asset.state = .FAILED;
                return;
            }
            if position_count >= positions.count {
                mesh.asset.state = .FAILED;
                return;
            }
            positions[position_count] = position;
            position_count += 1;
            continue;
        }
        if line.data[0] != #char "f" || line.data[1] != #char " " continue;
        indices: [3] s32;
        if !scan2(line, "f % % %", *indices[0], *indices[1], *indices[2]) {
            mesh.asset.state = .FAILED;
            return;
        }
        for 0..2 {
            indices[it] -= 1;
            if indices[it] < 0 || indices[it] >= position_count {
                mesh.asset.state = .FAILED;
                return;
            }
        }
        a := positions[indices[0]];
        b := positions[indices[1]];
        c := positions[indices[2]];
        normal := normalize(cross(b - a, c - a));
        array_add(*mesh.vertices, .{ position = a, normal = normal });
        array_add(*mesh.vertices, .{ position = b, normal = normal });
        array_add(*mesh.vertices, .{ position = c, normal = normal });
    }
    if mesh.vertices.count == 0 {
        mesh.asset.state = .FAILED;
    }
}

store_request_raw_asset :: (asset: *Store_Asset, platform: *Platform) {
    if asset.request != 0 return;
    asset.request = platform.system.asset_request_async(.{ data = asset.path.data, count = asset.path.count });
}

store_update_raw_asset :: (store: *Store, asset: *Store_Asset, platform: *Platform) {
    if asset.request == 0 return;
    status := platform.system.asset_get_status(asset.request);
    if status.state == .PENDING return;
    if status.state == .FAILED {
        asset.state = .FAILED;
        asset.request = 0;
        return;
    }
    allocator: Allocator = .{ store.pool_allocator_proc, *store.pool };
    asset.bytes = platform.system.asset_take(asset.request, allocator);
    asset.request = 0;
    if asset.bytes.count > 0 {
        asset.state = .READY;
        asset.version += 1;
    } else {
        asset.state = .FAILED;
    }
}

store_start_shader_watch :: (store: *Store, platform: *Platform) {
    if store.shader_watch != 0 return;
    if !platform.system.watch_file_changes || !platform.system.pull_watch_changes return;
    directory := "shaders";
    store.shader_watch = platform.system.watch_file_changes(.{
        data = directory.data,
        count = directory.count,
    });
}

store_request_changed_shader :: (store: *Store, path: string, platform: *Platform) {
    if ends_with(path, store.geometry_shader.asset.path) {
        if platform.system.log {
            message := tprint("shader file changed: %", path);
            platform.system.log(.{ data = message.data, count = message.count });
        }
        store_request_raw_asset(*store.geometry_shader.asset, platform);
    }
    if ends_with(path, store.gui_shader.asset.path) {
        if platform.system.log {
            message := tprint("shader file changed: %", path);
            platform.system.log(.{ data = message.data, count = message.count });
        }
        store_request_raw_asset(*store.gui_shader.asset, platform);
    }
}

store_update_shader_hot_reload :: (store: *Store, platform: *Platform) {
    if store.shader_watch == 0 || !platform.system.pull_watch_changes return;
    changes := platform.system.pull_watch_changes(store.shader_watch);
    for changes {
        if it.kind == .REMOVED continue;
        path: string = .{ data = it.path.data, count = it.path.count };
        store_request_changed_shader(store, path, platform);
    }
    store_update_raw_asset(store, *store.geometry_shader.asset, platform);
    store_update_raw_asset(store, *store.gui_shader.asset, platform);
}

store_init :: (store: *Store, platform: *Platform) {
    store.* = .{};
    set_allocators(*store.pool);
    store.pool_allocator_proc = platform.system.persistent_pool_allocator_proc;
    store.geometry_shader.asset.path = "shaders/triangle.wgsl";
    store.gui_shader.asset.path = "shaders/gui.wgsl";
    store.cube_mesh.asset.path = "meshes/cube.obj";
    store.sphere_mesh.asset.path = "meshes/sphere.obj";
    store.verdana_font.metrics_asset.path = "fonts/verdana.csv";
    store.verdana_font.atlas.asset.path = "fonts/verdana.qoi";
    if platform.system.log {
        block_allocator: Allocator_Proc_Bits;
        block_allocator.proc = store.pool.block_allocator.proc;
        message := tprint(
            "Store paths: geometry=% gui=% cube=% sphere=% font_metrics=% font_atlas=% block_proc=%",
            store.geometry_shader.asset.path,
            store.gui_shader.asset.path,
            store.cube_mesh.asset.path,
            store.sphere_mesh.asset.path,
            store.verdana_font.metrics_asset.path,
            store.verdana_font.atlas.asset.path,
            block_allocator.bits
        );
        platform.system.log(.{ data = message.data, count = message.count });
    }
}

store_unload :: (store: *Store) {
    release(*store.pool);
    store.* = .{};
}

store_load_platform_blob :: (store: *Store, platform: *Platform) {
    blob := platform.system.try_get_asset_blob();
    if blob.count > 0 {
        store_load_blob(store, blob, platform);
    }
}

store_set_blob_asset :: (asset: *Store_Asset, bytes: [] u8) {
    asset.bytes = bytes;
    asset.state = .READY;
    asset.version += 1;
}

store_read_u32_le :: (bytes: [] u8, offset: u64) -> u32 {
    return cast(u32) bytes[offset + 0] +
        cast(u32) bytes[offset + 1] * 0x00000100 +
        cast(u32) bytes[offset + 2] * 0x00010000 +
        cast(u32) bytes[offset + 3] * 0x01000000;
}

store_paths_equal :: (a: string, b: string) -> bool {
    return compare(a, b) == 0;
}

store_load_blob :: (store: *Store, blob: [] u8, platform: *Platform) {
    if blob.count < 16 return;
    cursor: u64 = 16;
    asset_count := store_read_u32_le(blob, 12);
    for 0..asset_count - 1 {
        if cursor + 4 > xx blob.count return;
        path_count := store_read_u32_le(blob, cursor);
        cursor += 4;
        metrics_loaded := false;
        atlas_loaded := false;
        for 0..path_count - 1 {
            if cursor + 8 > xx blob.count return;
            path_count_bytes := store_read_u32_le(blob, cursor);
            data_count := store_read_u32_le(blob, cursor + 4);
            cursor += 8;
            if cursor + path_count_bytes + data_count > xx blob.count return;
            path: [] u8 = .{ data = blob.data + cursor, count = xx path_count_bytes };
            cursor += path_count_bytes;
            data: [] u8 = .{ data = blob.data + cursor, count = xx data_count };
            cursor += data_count;
            path_string: string = .{ data = path.data, count = path.count };
            if platform.system.log {
                message := tprint(
                    "Store loading asset: % cube_match=% sphere_match=%",
                    path_string,
                    store_paths_equal(path_string, store.cube_mesh.asset.path),
                    store_paths_equal(path_string, store.sphere_mesh.asset.path)
                );
                platform.system.log(.{ data = message.data, count = message.count });
            }
            if store_paths_equal(path_string, store.geometry_shader.asset.path) {
                store_set_blob_asset(*store.geometry_shader.asset, data);
            }
            if store_paths_equal(path_string, store.gui_shader.asset.path) {
                store_set_blob_asset(*store.gui_shader.asset, data);
            }
            if store_paths_equal(path_string, store.cube_mesh.asset.path) {
                store_set_blob_asset(*store.cube_mesh.asset, data);
                if platform.system.log {
                    message := "Store promoting cube mesh";
                    platform.system.log(.{ data = message.data, count = message.count });
                }
                store_promote_obj_mesh(*store.cube_mesh, store);
                if platform.system.log {
                    message := "Store promoted cube mesh";
                    platform.system.log(.{ data = message.data, count = message.count });
                }
            }
            if store_paths_equal(path_string, store.sphere_mesh.asset.path) {
                store_set_blob_asset(*store.sphere_mesh.asset, data);
                if platform.system.log {
                    message := "Store promoting sphere mesh";
                    platform.system.log(.{ data = message.data, count = message.count });
                }
                store_promote_obj_mesh(*store.sphere_mesh, store);
                if platform.system.log {
                    message := "Store promoted sphere mesh";
                    platform.system.log(.{ data = message.data, count = message.count });
                }
            }
            if store_paths_equal(path_string, store.verdana_font.metrics_asset.path) {
                store_set_blob_asset(*store.verdana_font.metrics_asset, data);
                metrics_loaded = true;
            }
            if store_paths_equal(path_string, store.verdana_font.atlas.asset.path) {
                store_set_blob_asset(*store.verdana_font.atlas.asset, data);
                atlas_loaded = true;
            }
        }
        if atlas_loaded {
            if platform.system.log {
                message := "Store promoting font atlas";
                platform.system.log(.{ data = message.data, count = message.count });
            }
            store_promote_qoi_texture(*store.verdana_font.atlas, store, platform);
        }
        if metrics_loaded || atlas_loaded {
            if platform.system.log {
                message := "Store promoting font metrics";
                platform.system.log(.{ data = message.data, count = message.count });
            }
            store_promote_font_metrics(*store.verdana_font, store);
        }
    }
}
