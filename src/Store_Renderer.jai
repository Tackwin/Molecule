store_upload_gpu_assets :: (store: *Store, renderer: *Renderer, platform: *Platform) -> bool {
    if !renderer_upload_mesh_asset(renderer, platform, *store.cube_mesh) {
        return false;
    }
    if !renderer_upload_mesh_asset(renderer, platform, *store.sphere_mesh) {
        return false;
    }
    if !renderer_upload_mesh_asset(renderer, platform, *store.empty_tile) {
        return false;
    }
    if !renderer_upload_mesh_asset(renderer, platform, *store.methane) {
        return false;
    }
    if !renderer_upload_texture_asset(renderer, platform, *store.verdana_font.atlas) {
        return false;
    }
    if !renderer_upload_texture_asset(renderer, platform, *store.palette) {
        return false;
    }
    if !renderer_rebuild_asset_bind_groups(renderer, platform, *store.verdana_font.atlas, *store.palette) {
        return false;
    }
    return true;
}
