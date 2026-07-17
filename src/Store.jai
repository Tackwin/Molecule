#import "Basic";
#import "Pool";
#import "platform";

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
    allocator: Allocator = .{ pool_allocator_proc, *store.pool };
    asset.bytes = platform.system.asset_take(asset.request, allocator);
    asset.request = 0;
    if asset.bytes.count > 0 {
        asset.state = .READY;
        asset.version += 1;
    } else {
        asset.state = .FAILED;
    }
}

Shader_Asset :: struct {
    asset: Store_Asset;
}

Store :: struct {
    pool: Pool;
    triangle_shader: Shader_Asset;
}

store_init :: (store: *Store) {
    store.* = .{};
    store.triangle_shader.asset.path = "shaders/triangle.wgsl";
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
        path: [] u8 = .{ data = blob.data + cursor, count = xx path_count };
        cursor += path_count;
        data: [] u8 = .{ data = blob.data + cursor, count = xx data_count };
        cursor += data_count;
        path_string: string = .{ data = path.data, count = path.count };
        if path_string == store.triangle_shader.asset.path {
            store_set_blob_asset(*store.triangle_shader.asset, data);
        }
    }
}
