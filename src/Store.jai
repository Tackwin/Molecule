#import "Basic";
#import "String";
#import "Pool";
#import "Hash";
#import "Hash_Table";
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
    uv: V2f;
    uv_padding: V2f;
}

Mesh_Triangle :: struct {
    normal: V3f;
    normal_padding: float32;
    edge_cavity: V3f;
    cavity_padding: float32;
}

Mesh_Asset :: struct {
    asset: Store_Asset;
    vertices: [..] Mesh_Vertex;
    triangles: [..] Mesh_Triangle;
    gpu_vertex_offset: u32;
    gpu_vertex_count: u32;
    gpu_triangle_offset: u32;
    gpu_triangle_count: u32;
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
    post_shader: Shader_Asset;
    cube_mesh: Mesh_Asset;
    sphere_mesh: Mesh_Asset;
    palette: Texture_Asset;
    verdana_font: Font_Asset;

    empty_tile: Mesh_Asset;
    methane: Mesh_Asset;
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
    next_line :: (remaining: *string) -> string {
        found, line, tail := split_from_left(remaining.*, #char "\n");
        if found {
            remaining.* = tail;
            return line;
        }
        line = remaining.*;
        remaining.* = "";
        return line;
    }

    if font.metrics_asset.bytes.count == 0 return;
    if font.atlas.width == 0 || font.atlas.height == 0 return;
    if font.glyphs[65].advance != 0 return;
    text: string = .{ data = font.metrics_asset.bytes.data, count = font.metrics_asset.bytes.count };
    while text.count > 0 {
        line := next_line(*text);
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

store_build_mesh_triangles :: (mesh: *Mesh_Asset, store: *Store) {
    Edge_Key :: struct {
        a: V3f;
        b: V3f;
    }

    Edge_Use :: struct {
        triangle_indices: [2] s32;
        edge_indices: [2] s32;
        count: s32;
    }

    position_less :: (a: V3f, b: V3f) -> bool {
        if a.x != b.x return a.x < b.x;
        if a.y != b.y return a.y < b.y;
        return a.z < b.z;
    }

    make_edge_key :: (start: V3f, end: V3f) -> Edge_Key {
        if position_less(end, start) {
            return .{ end, start };
        }
        return .{ start, end };
    }

    hash_edge_key :: (key: Edge_Key) -> u32 {
        hash := sdbm_float_hash(*key.a.x, 3);
        return sdbm_float_hash(*key.b.x, 3, hash);
    }

    compare_edge_keys :: (a: Edge_Key, b: Edge_Key) -> bool {
        return a.a == b.a && a.b == b.b;
    }

    get_triangle_edge :: (mesh: *Mesh_Asset, triangle_index: int, edge_index: int) -> V3f, V3f {
        vertex_offset := triangle_index * 3;
        if edge_index == 0 {
            return mesh.vertices[vertex_offset + 1].position, mesh.vertices[vertex_offset + 2].position;
        }
        if edge_index == 1 {
            return mesh.vertices[vertex_offset + 2].position, mesh.vertices[vertex_offset + 0].position;
        }
        return mesh.vertices[vertex_offset + 0].position, mesh.vertices[vertex_offset + 1].position;
    }

    set_edge_cavity :: (triangle: *Mesh_Triangle, edge_index: int, cavity: float32) {
        if edge_index == 0 {
            triangle.edge_cavity.x = cavity;
        } else if edge_index == 1 {
            triangle.edge_cavity.y = cavity;
        } else {
            triangle.edge_cavity.z = cavity;
        }
    }

    triangle_count := mesh.vertices.count / 3;
    mesh.triangles.allocator = .{ store.pool_allocator_proc, *store.pool };
    array_resize(*mesh.triangles, triangle_count);
    for triangle_index: 0..triangle_count - 1 {
        vertex_offset := triangle_index * 3;
        p0 := mesh.vertices[vertex_offset + 0].position;
        p1 := mesh.vertices[vertex_offset + 1].position;
        p2 := mesh.vertices[vertex_offset + 2].position;
        triangle: Mesh_Triangle = .{};
        triangle.normal = normalize(cross(p1 - p0, p2 - p0));
        mesh.triangles[triangle_index] = triangle;
    }

    edge_uses: Table(Edge_Key, Edge_Use, hash_edge_key, compare_edge_keys);
    edge_uses.allocator = temp;
    init(*edge_uses, triangle_count * 6);
    for triangle_index: 0..triangle_count - 1 {
        for edge_index: 0..2 {
            edge_start, edge_end := get_triangle_edge(mesh, triangle_index, edge_index);
            key := make_edge_key(edge_start, edge_end);
            edge_use, _ := find_or_add(*edge_uses, key);
            if edge_use.count < 2 {
                edge_use.triangle_indices[edge_use.count] = cast(s32) triangle_index;
                edge_use.edge_indices[edge_use.count] = cast(s32) edge_index;
            }
            edge_use.count += 1;
        }
    }

    for edge_uses {
        if it.count != 2 continue;
        for side: 0..1 {
            triangle_index := cast(int) it.triangle_indices[side];
            edge_index := cast(int) it.edge_indices[side];
            neighbor_index := cast(int) it.triangle_indices[1 - side];
            edge_start, edge_end := get_triangle_edge(mesh, triangle_index, edge_index);
            edge_direction := normalize(edge_end - edge_start);
            normal := mesh.triangles[triangle_index].normal;
            neighbor_normal := mesh.triangles[neighbor_index].normal;
            signed_dihedral := dot(edge_direction, cross(normal, neighbor_normal));
            set_edge_cavity(*mesh.triangles[triangle_index], edge_index, signed_dihedral);
        }
    }
}

store_promote_obj_mesh :: (mesh: *Mesh_Asset, store: *Store) {
    if mesh.asset.bytes.count == 0 || mesh.vertices.count > 0 return;
    mesh.vertices.allocator = .{ store.pool_allocator_proc, *store.pool };
    positions: [..] V3f;
    positions.allocator = temp;
    uvs: [..] V2f;
    uvs.allocator = temp;
    text: string = .{ data = mesh.asset.bytes.data, count = mesh.asset.bytes.count };

    lines := split(text, #char "\n",, temp);
    for lines {
        line := trim(it, " \t\r");
        if line.count == 0 || line.data[0] == #char "#"
            continue;

        position: V3f;
        uv: V2f;
        if scan2(line, "v % % %", *position.x, *position.y, *position.z) {
            array_add(*positions, position);
            continue;
        }
        if scan2(line, "vt % %", *uv.x, *uv.y) {
            array_add(*uvs, uv);
            continue;
        }

        v_indices: [3] int;
        n_indices: [3] int;
        t_indices: [3] int;
        if scan2(
            line,
            "f %/%/% %/%/% %/%/%",
            *v_indices[0], *t_indices[0], *n_indices[0],
            *v_indices[1], *t_indices[1], *n_indices[1],
            *v_indices[2], *t_indices[2], *n_indices[2]
        ) {
            ok := true;
            for 0..2
                ok &= 0 < v_indices[it] && v_indices[it] <= positions.count
                    && 0 < t_indices[it] && t_indices[it] <= uvs.count;
            if !ok
                continue;

            for 0..2 {
                v: Mesh_Vertex = .{};
                v.position = positions[v_indices[it] - 1];
                v.uv = uvs[t_indices[it] - 1];
                array_add(*mesh.vertices, v);
            }
            continue;
        }
        if scan2(line, "f %//% %//% %//%", *v_indices[0], *n_indices[0], *v_indices[1], *n_indices[1], *v_indices[2],
            *n_indices[2]) {
            ok := true;
            for 0..2
                ok &= 0 < v_indices[it] && v_indices[it] <= positions.count;
            if !ok
                continue;

            for 0..2 {
                v: Mesh_Vertex = .{};
                v.position = positions[v_indices[it] - 1];
                array_add(*mesh.vertices, v);
            }
            continue;
        }
        if scan2(line, "f %/% %/% %/%", *v_indices[0], *t_indices[0], *v_indices[1], *t_indices[1], *v_indices[2],
            *t_indices[2]) {
            ok := true;
            for 0..2
                ok &= 0 < v_indices[it] && v_indices[it] <= positions.count
                    && 0 < t_indices[it] && t_indices[it] <= uvs.count;
            if !ok
                continue;

            for 0..2 {
                v: Mesh_Vertex = .{};
                v.position = positions[v_indices[it] - 1];
                v.uv = uvs[t_indices[it] - 1];
                array_add(*mesh.vertices, v);
            }
            continue;
        }
        if scan2(line, "f % % %", *v_indices[0], *v_indices[1], *v_indices[2]) {
            ok := true;
            for 0..2
                ok &= 0 < v_indices[it] && v_indices[it] <= positions.count;
            if !ok
                continue;

            for 0..2 {
                v: Mesh_Vertex = .{};
                v.position = positions[v_indices[it] - 1];
                array_add(*mesh.vertices, v);
            }
            continue;
        }
    }
    if mesh.vertices.count == 0 || mesh.vertices.count % 3 != 0 {
        mesh.asset.state = .FAILED;
        return;
    }
    store_build_mesh_triangles(mesh, store);
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
    if ends_with(path, store.post_shader.asset.path) {
        if platform.system.log {
            message := tprint("shader file changed: %", path);
            platform.system.log(.{ data = message.data, count = message.count });
        }
        store_request_raw_asset(*store.post_shader.asset, platform);
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
    store_update_raw_asset(store, *store.post_shader.asset, platform);
}

store_init :: (store: *Store, platform: *Platform) {
    store.* = .{};
    set_allocators(*store.pool);
    store.pool_allocator_proc = platform.system.persistent_pool_allocator_proc;
    store.geometry_shader.asset.path = "shaders/triangle.wgsl";
    store.gui_shader.asset.path = "shaders/gui.wgsl";
    store.post_shader.asset.path = "shaders/post.wgsl";
    store.cube_mesh.asset.path = "meshes/cube.obj";
    store.empty_tile.asset.path = "meshes/empty_tile.obj";
    store.methane.asset.path = "meshes/methane.obj";
    store.sphere_mesh.asset.path = "meshes/sphere.obj";
    store.palette.asset.path = "textures/palette.qoi";
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
        palette_loaded := false;
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
            if store_paths_equal(path_string, store.geometry_shader.asset.path) {
                store_set_blob_asset(*store.geometry_shader.asset, data);
            }
            if store_paths_equal(path_string, store.gui_shader.asset.path) {
                store_set_blob_asset(*store.gui_shader.asset, data);
            }
            if store_paths_equal(path_string, store.post_shader.asset.path) {
                store_set_blob_asset(*store.post_shader.asset, data);
            }
            if store_paths_equal(path_string, store.empty_tile.asset.path) {
                store_set_blob_asset(*store.empty_tile.asset, data);
                log(platform, "Store promoting empty tile mesh");
                store_promote_obj_mesh(*store.empty_tile, store);
                log(platform, "Store promoted empty tile mesh");
            }
            if store_paths_equal(path_string, store.methane.asset.path) {
                store_set_blob_asset(*store.methane.asset, data);
                log(platform, "Store promoting methane mesh");
                store_promote_obj_mesh(*store.methane, store);
                log(platform, "Store promoted methane mesh");
            }
            if store_paths_equal(path_string, store.cube_mesh.asset.path) {
                store_set_blob_asset(*store.cube_mesh.asset, data);
                log(platform, "Store promoting cube mesh");
                store_promote_obj_mesh(*store.cube_mesh, store);
                log(platform, "Store promoted cube mesh");
            }
            if store_paths_equal(path_string, store.sphere_mesh.asset.path) {
                store_set_blob_asset(*store.sphere_mesh.asset, data);
                log(platform, "Store promoting sphere mesh");
                store_promote_obj_mesh(*store.sphere_mesh, store);
                log(platform, "Store promoted sphere mesh");
            }
            if store_paths_equal(path_string, store.verdana_font.metrics_asset.path) {
                store_set_blob_asset(*store.verdana_font.metrics_asset, data);
                metrics_loaded = true;
            }
            if store_paths_equal(path_string, store.verdana_font.atlas.asset.path) {
                store_set_blob_asset(*store.verdana_font.atlas.asset, data);
                atlas_loaded = true;
            }
            if store_paths_equal(path_string, store.palette.asset.path) {
                store_set_blob_asset(*store.palette.asset, data);
                palette_loaded = true;
            }
        }
        if atlas_loaded {
            log(platform, "Store promoting font atlas");
            store_promote_qoi_texture(*store.verdana_font.atlas, store, platform);
        }
        if metrics_loaded || atlas_loaded {
            log(platform, "Store promoting font metrics");
            store_promote_font_metrics(*store.verdana_font, store);
        }
        if palette_loaded {
            log(platform, "Store promoting palette texture");
            store_promote_qoi_texture(*store.palette, store, platform);
        }
    }
}
