#import "Basic";
#import "String";
#import "Pool";
#import "platform";
#import "Algebra";

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

Store :: struct {
    pool: Pool;
    pool_allocator_proc: Allocator_Proc;
    geometry_shader: Shader_Asset;
    cube_mesh: Mesh_Asset;
    sphere_mesh: Mesh_Asset;
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

store_init :: (store: *Store, platform: *Platform) {
    store.* = .{};
    set_allocators(*store.pool);
    store.pool_allocator_proc = platform.system.persistent_pool_allocator_proc;
    store.geometry_shader.asset.path = "shaders/triangle.wgsl";
    store.cube_mesh.asset.path = "meshes/cube.obj";
    store.sphere_mesh.asset.path = "meshes/sphere.obj";
}

store_unload :: (store: *Store) {
    release(*store.pool);
    store.* = .{};
}

store_load_platform_blob :: (store: *Store, platform: *Platform) {
    blob := platform.system.try_get_asset_blob();
    if blob.count > 0 {
        store_load_blob(store, blob);
    }
}

store_set_blob_asset :: (asset: *Store_Asset, bytes: [] u8) {
    asset.bytes = bytes;
    asset.state = .READY;
    asset.version += 1;
}

store_load_blob :: (store: *Store, blob: [] u8) {
    if blob.count < 16 return;
    cursor: u64 = 16;
    while cursor + 8 <= xx blob.count {
        path_count := cast(u32) blob.data[cursor] | cast(u32) blob.data[cursor + 1] << 8;
        data_count := cast(u32) blob.data[cursor + 4];
        data_count += cast(u32) blob.data[cursor + 5] * 256;
        data_count += cast(u32) blob.data[cursor + 6] * 65536;
        data_count += cast(u32) blob.data[cursor + 7] * 16777216;
        cursor += 8;
        if cursor + path_count + data_count > xx blob.count return;
        path: [] u8 = .{ data = blob.data + cursor, count = xx path_count };
        cursor += path_count;
        data: [] u8 = .{ data = blob.data + cursor, count = xx data_count };
        cursor += data_count;
        path_string: string = .{ data = path.data, count = path.count };
        if path_string == store.geometry_shader.asset.path {
            store.geometry_shader.asset.bytes = data;
            store.geometry_shader.asset.state = .READY;
            store.geometry_shader.asset.version += 1;
        }
        if path_string == store.cube_mesh.asset.path {
            store.cube_mesh.asset.bytes = data;
            store.cube_mesh.asset.state = .READY;
            store.cube_mesh.asset.version += 1;
            store_promote_obj_mesh(*store.cube_mesh, store);
        }
        if path_string == store.sphere_mesh.asset.path {
            store.sphere_mesh.asset.bytes = data;
            store.sphere_mesh.asset.state = .READY;
            store.sphere_mesh.asset.version += 1;
            store_promote_obj_mesh(*store.sphere_mesh, store);
        }
    }
}
