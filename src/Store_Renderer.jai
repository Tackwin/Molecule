store_upload_gpu_assets :: (store: *Store, renderer: *Renderer, platform: *Platform) -> bool {
    if !renderer_upload_mesh_asset(renderer, platform, *store.cube_mesh) {
        return false;
    }
    if !renderer_upload_mesh_asset(renderer, platform, *store.sphere_mesh) {
        return false;
    }
    if !renderer_upload_texture_asset(renderer, platform, *store.verdana_font.atlas) {
        return false;
    }
    return true;
}
