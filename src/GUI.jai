#import "Basic";
#import "Math";
#import "Algebra";
#import "platform";
#import "Store";
#import "Hash_Table";
#import "Pool";

GUI_MAX_QUADS :: 4096;

Gui_Quad_Kind :: enum u32 {
    Solid;
    Font_MSDF;
}

Gui_Quad :: struct {
    position_pixels: V2f;
    size_pixels: V2f;
    color: V4f;
    uv_rect: V4f;
    z: float32;
    kind: Gui_Quad_Kind;
    outline_width_pixels: float32;
}

Gui_Widget :: struct {
    bounds: V4f;
    z: float32;
    touched: bool;
    hovered: bool;
    pressed: bool;
    released: bool;
}

Gui_Layout_Direction :: enum {
    Right;
    Down;
}

Gui_Layout_Scope :: struct {
    cursor_pixels: V2f;
    z: float32;
    direction: Gui_Layout_Direction;
    gap_pixels: V2f;
    child_bounds: V4f;
    has_children: bool;
}

Gui_Prepared_Glyph :: struct {
    position_offset_pixels: V2f;
    size_pixels: V2f;
    uv_rect: V4f;
}

Gui_Prepared_Text :: struct {
    bounds_offset_pixels: V4f;
    size_pixels: V2f;
    glyphs: [] Gui_Prepared_Glyph;
    caret_x_offsets: [] float32;
}

GUI_State :: struct {
    frame_pool: Pool;
    persistent_pool: Pool;
    quads: [..] Gui_Quad;
    widgets: Table(u64, Gui_Widget);
    id_stack: [..] u64;
    layout_stack: [..] Gui_Layout_Scope;
    prepared_glyphs: [GUI_MAX_QUADS] Gui_Prepared_Glyph;
    prepared_glyph_count: s32;
    caret_x_offsets: [GUI_MAX_QUADS + 1] float32;
    caret_x_offset_count: s32;
    mouse_position_pixels: V2f;
    mouse_left_down: bool;
    mouse_left_pressed: bool;
    mouse_left_released: bool;
    mouse_captured: bool;
    font: *Font_Asset;
}

gui_init :: (gui: *GUI_State) {
    set_allocators(*gui.frame_pool);
    set_allocators(*gui.persistent_pool);
    frame_allocator: Allocator = .{ pool_allocator_proc, *gui.frame_pool };
    persistent_allocator: Allocator = .{ pool_allocator_proc, *gui.persistent_pool };
    gui.quads.allocator = frame_allocator;
    gui.id_stack.allocator = frame_allocator;
    gui.layout_stack.allocator = frame_allocator;
    gui.widgets.allocator = persistent_allocator;
}

gui_reset_frame_storage :: (gui: *GUI_State) {
    array_reset(*gui.quads);
    array_reset(*gui.id_stack);
    array_reset(*gui.layout_stack);
    reset(*gui.frame_pool);
}

gui_hash_string :: (text: string) -> u64 {
    hash: u64 = 14695981039346656037;
    for text {
        hash ^= it;
        hash *= 1099511628211;
    }
    return hash;
}

gui_combine_id :: (a: u64, b: u64) -> u64 {
    return a ^ (b + 0x9e3779b97f4a7c15 + (a << 6) + (a >> 2));
}

gui_last_id :: (gui: *GUI_State) -> u64 {
    if gui.id_stack.count == 0 return 0;
    return gui.id_stack[gui.id_stack.count - 1];
}

gui_push_id :: (gui: *GUI_State, id: u64) {
    array_add(*gui.id_stack, gui_combine_id(gui_last_id(gui), id));
}

gui_push_id :: (gui: *GUI_State, id: string) {
    gui_push_id(gui, gui_hash_string(id));
}

gui_pop_id :: (gui: *GUI_State) {
    if gui.id_stack.count > 0 gui.id_stack.count -= 1;
}

gui_begin_frame :: (gui: *GUI_State, input: *Frame_Input, font: *Font_Asset) {
    gui_reset_frame_storage(gui);
    gui.font = font;
    gui.mouse_position_pixels = .{
        cast(float32) input.mouse.position_pixels.x,
        cast(float32) input.mouse.position_pixels.y,
    };
    gui.mouse_left_down = (input.mouse.buttons_down & 1) != 0;
    gui.mouse_left_pressed = (input.mouse.buttons_pressed & 1) != 0;
    gui.mouse_left_released = (input.mouse.buttons_released & 1) != 0;
    gui.mouse_captured = false;

    for *widget, key: gui.widgets {
        widget.hovered = gui.mouse_position_pixels.x >= widget.bounds.x &&
            gui.mouse_position_pixels.y >= widget.bounds.y &&
            gui.mouse_position_pixels.x < widget.bounds.z &&
            gui.mouse_position_pixels.y < widget.bounds.w;
        widget.pressed = widget.hovered && gui.mouse_left_pressed;
        widget.released = widget.hovered && gui.mouse_left_released;
        if widget.hovered && (gui.mouse_left_down || gui.mouse_left_pressed || gui.mouse_left_released) {
            gui.mouse_captured = true;
        }
        widget.touched = false;
    }

    gui.prepared_glyph_count = 0;
    gui.caret_x_offset_count = 0;
}

gui_end_frame :: (gui: *GUI_State) {
    for *widget, key: gui.widgets {
        if !widget.touched {
            remove key;
        }
    }
}

gui_bounds_union :: (a: V4f, b: V4f) -> V4f {
    return .{ min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w) };
}

gui_layout_add_child :: (gui: *GUI_State, bounds: V4f) {
    if gui.layout_stack.count == 0 return;
    scope := *gui.layout_stack[gui.layout_stack.count - 1];
    if scope.has_children {
        scope.child_bounds = gui_bounds_union(scope.child_bounds, bounds);
    } else {
        scope.child_bounds = bounds;
        scope.has_children = true;
    }
    if scope.direction == .Right {
        scope.cursor_pixels.x = bounds.z + scope.gap_pixels.x;
    } else {
        scope.cursor_pixels.y = bounds.w + scope.gap_pixels.y;
    }
}

gui_begin_column :: (gui: *GUI_State, cursor_pixels: V2f, z: float32 = 0, gap_pixels: V2f = .{ 6, 6 }) {
    array_add(*gui.layout_stack, .{
        cursor_pixels = cursor_pixels,
        z = z,
        direction = .Down,
        gap_pixels = gap_pixels,
    });
}

gui_push_row :: (gui: *GUI_State) {
    assert(gui.layout_stack.count > 0);
    parent := gui.layout_stack[gui.layout_stack.count - 1];
    array_add(*gui.layout_stack, .{
        cursor_pixels = parent.cursor_pixels,
        z = parent.z,
        direction = .Right,
        gap_pixels = parent.gap_pixels,
    });
}

gui_push_column :: (gui: *GUI_State) {
    assert(gui.layout_stack.count > 0);
    parent := gui.layout_stack[gui.layout_stack.count - 1];
    array_add(*gui.layout_stack, .{
        cursor_pixels = parent.cursor_pixels,
        z = parent.z,
        direction = .Down,
        gap_pixels = parent.gap_pixels,
    });
}

gui_pop_layout :: (gui: *GUI_State) -> V4f {
    assert(gui.layout_stack.count > 0);
    scope := gui.layout_stack[gui.layout_stack.count - 1];
    gui.layout_stack.count -= 1;
    if gui.layout_stack.count > 0 && scope.has_children {
        gui_layout_add_child(gui, scope.child_bounds);
    }
    return scope.child_bounds;
}

gui_layout_cursor :: (gui: *GUI_State) -> V2f {
    assert(gui.layout_stack.count > 0);
    return gui.layout_stack[gui.layout_stack.count - 1].cursor_pixels;
}

gui_layout_z :: (gui: *GUI_State) -> float32 {
    assert(gui.layout_stack.count > 0);
    return gui.layout_stack[gui.layout_stack.count - 1].z;
}

gui_push_quad :: (gui: *GUI_State, quad: Gui_Quad) {
    if gui.quads.count >= GUI_MAX_QUADS return;
    array_add(*gui.quads, quad);
}

gui_quad :: (gui: *GUI_State, position_pixels: V2f, size_pixels: V2f, color: V4f, z: float32 = 0) {
    gui_push_quad(gui, .{
        position_pixels = position_pixels,
        size_pixels = size_pixels,
        color = color,
        z = z,
        kind = .Solid,
    });
}

gui_panel :: (gui: *GUI_State, position_pixels: V2f, size_pixels: V2f, color: V4f, z: float32 = 0) {
    gui_quad(gui, position_pixels, size_pixels, color, z);
}

gui_separator :: (gui: *GUI_State, position_pixels: V2f, width_pixels: float32, z: float32 = 0) -> V4f {
    bounds: V4f = .{ position_pixels.x, position_pixels.y, position_pixels.x + width_pixels, position_pixels.y + 1 };
    gui_quad(gui, position_pixels, .{ width_pixels, 1 }, .{ 0.24, 0.34, 0.46, 1 }, z);
    return bounds;
}

gui_separator_flow :: (gui: *GUI_State, width_pixels: float32) -> V4f {
    bounds := gui_separator(gui, gui_layout_cursor(gui), width_pixels, gui_layout_z(gui));
    gui_layout_add_child(gui, bounds);
    return bounds;
}

gui_prepare_text :: (gui: *GUI_State, text: string, scale: float32 = 16) -> Gui_Prepared_Text {
    result: Gui_Prepared_Text;
    glyph_start := gui.prepared_glyph_count;
    caret_start := gui.caret_x_offset_count;
    if caret_start >= gui.caret_x_offsets.count return result;
    gui.caret_x_offsets[caret_start] = 0;
    gui.caret_x_offset_count += 1;
    if !gui.font return result;
    cursor_x: float32 = 0;
    bounds: V4f = .{ FLOAT32_MAX, FLOAT32_MAX, -FLOAT32_MAX, -FLOAT32_MAX };
    for text {
        if it < gui.font.glyphs.count {
            glyph := gui.font.glyphs[it];
            if glyph.advance != 0 {
                if gui.prepared_glyph_count < gui.prepared_glyphs.count {
                    prepared := *gui.prepared_glyphs[gui.prepared_glyph_count];
                    prepared.* = .{
                        position_offset_pixels = .{ cursor_x + glyph.plane_x * scale, glyph.plane_y * scale },
                        size_pixels = .{ (glyph.plane_width - glyph.plane_x) * scale, (glyph.plane_height - glyph.plane_y) * scale },
                        uv_rect = glyph.uv_rect,
                    };
                    bounds = gui_bounds_union(bounds, .{
                        prepared.position_offset_pixels.x,
                        prepared.position_offset_pixels.y,
                        prepared.position_offset_pixels.x + prepared.size_pixels.x,
                        prepared.position_offset_pixels.y + prepared.size_pixels.y,
                    });
                    gui.prepared_glyph_count += 1;
                }
                cursor_x += glyph.advance * scale;
            }
        }
        if gui.caret_x_offset_count < gui.caret_x_offsets.count {
            gui.caret_x_offsets[gui.caret_x_offset_count] = cursor_x;
            gui.caret_x_offset_count += 1;
        }
    }
    if gui.prepared_glyph_count == glyph_start {
        bounds = .{ 0, 0, 0, 0 };
    }
    result.bounds_offset_pixels = bounds;
    result.size_pixels = .{ bounds.z - bounds.x, bounds.w - bounds.y };
    result.glyphs.data = *gui.prepared_glyphs[glyph_start];
    result.glyphs.count = gui.prepared_glyph_count - glyph_start;
    result.caret_x_offsets.data = *gui.caret_x_offsets[caret_start];
    result.caret_x_offsets.count = gui.caret_x_offset_count - caret_start;
    return result;
}

gui_place_prepared_text :: (
    gui: *GUI_State, prepared: Gui_Prepared_Text, origin_pixels: V2f,
    color: V4f = .{ 1, 1, 1, 1 }, z: float32 = 0, outline_width_pixels: float32 = 0
) -> V4f {
    for prepared.glyphs {
        gui_push_quad(gui, .{
            position_pixels = origin_pixels + it.position_offset_pixels,
            size_pixels = it.size_pixels,
            color = color,
            uv_rect = it.uv_rect,
            z = z,
            kind = .Font_MSDF,
            outline_width_pixels = outline_width_pixels,
        });
    }
    return .{
        origin_pixels.x + prepared.bounds_offset_pixels.x,
        origin_pixels.y + prepared.bounds_offset_pixels.y,
        origin_pixels.x + prepared.bounds_offset_pixels.z,
        origin_pixels.y + prepared.bounds_offset_pixels.w,
    };
}

gui_label :: (
    gui: *GUI_State, text: string, position_pixels: V2f, scale: float32 = 16,
    color: V4f = .{ 1, 1, 1, 1 }, z: float32 = 0, outline_width_pixels: float32 = 0
) -> V4f {
    prepared := gui_prepare_text(gui, text, scale);
    return gui_place_prepared_text(gui, prepared, position_pixels, color, z, outline_width_pixels);
}

gui_label_flow :: (
    gui: *GUI_State, text: string, scale: float32 = 16, color: V4f = .{ 1, 1, 1, 1 },
    outline_width_pixels: float32 = 0
) -> V4f {
    prepared := gui_prepare_text(gui, text, scale);
    cursor := gui_layout_cursor(gui);
    origin := cursor - .{ prepared.bounds_offset_pixels.x, prepared.bounds_offset_pixels.y };
    bounds := gui_place_prepared_text(gui, prepared, origin, color, gui_layout_z(gui), outline_width_pixels);
    gui_layout_add_child(gui, bounds);
    return bounds;
}

gui_button :: (gui: *GUI_State, id: string, text: string, position_pixels: V2f, z: float32 = 0) -> bool {
    full_id := gui_combine_id(gui_last_id(gui), gui_hash_string(id));
    widget := table_find_pointer(*gui.widgets, full_id);
    if !widget {
        table_add(*gui.widgets, full_id, .{});
        widget = table_find_pointer(*gui.widgets, full_id);
    }
    widget.touched = true;
    prepared := gui_prepare_text(gui, text, 14);
    width := prepared.size_pixels.x + 12;
    widget.bounds = .{ position_pixels.x, position_pixels.y, position_pixels.x + width, position_pixels.y + 26 };
    widget.z = z;
    background := ifx widget.hovered then V4f.{ 0.16, 0.31, 0.48, 1 } else V4f.{ 0.08, 0.15, 0.24, 1 };
    gui_quad(gui, position_pixels, .{ width, 26 }, background, z);
    gui_place_prepared_text(gui, prepared, position_pixels + .{ 6 - prepared.bounds_offset_pixels.x, 5 - prepared.bounds_offset_pixels.y }, .{ 0.9, 0.94, 1, 1 }, z + 0.01);
    return widget.released;
}

gui_button_flow :: (gui: *GUI_State, id: string, text: string) -> bool {
    position := gui_layout_cursor(gui);
    clicked := gui_button(gui, id, text, position, gui_layout_z(gui));
    widget := table_find_pointer(*gui.widgets, gui_combine_id(gui_last_id(gui), gui_hash_string(id)));
    gui_layout_add_child(gui, widget.bounds);
    return clicked;
}

gui_checkbox :: (gui: *GUI_State, id: string, text: string, value: *bool, position_pixels: V2f, z: float32 = 0) -> bool {
    full_id := gui_combine_id(gui_last_id(gui), gui_hash_string(id));
    widget := table_find_pointer(*gui.widgets, full_id);
    if !widget {
        table_add(*gui.widgets, full_id, .{});
        widget = table_find_pointer(*gui.widgets, full_id);
    }
    widget.touched = true;
    prepared := gui_prepare_text(gui, text, 14);
    width := 22 + 6 + prepared.size_pixels.x;
    widget.bounds = .{ position_pixels.x, position_pixels.y, position_pixels.x + width, position_pixels.y + 22 };
    widget.z = z;
    box_color := ifx widget.hovered then V4f.{ 0.17, 0.31, 0.48, 1 } else V4f.{ 0.07, 0.14, 0.23, 1 };
    gui_quad(gui, position_pixels, .{ 22, 22 }, box_color, z);
    if value.* {
        gui_quad(gui, position_pixels + .{ 5, 5 }, .{ 12, 12 }, .{ 0.32, 0.78, 1, 1 }, z + 0.01);
    }
    gui_place_prepared_text(gui, prepared, position_pixels + .{ 28 - prepared.bounds_offset_pixels.x, 3 - prepared.bounds_offset_pixels.y }, .{ 0.87, 0.92, 1, 1 }, z + 0.01);
    if widget.released {
        value.* = !value.*;
        return true;
    }
    return false;
}

gui_checkbox_flow :: (gui: *GUI_State, id: string, text: string, value: *bool) -> bool {
    clicked := gui_checkbox(gui, id, text, value, gui_layout_cursor(gui), gui_layout_z(gui));
    widget := table_find_pointer(*gui.widgets, gui_combine_id(gui_last_id(gui), gui_hash_string(id)));
    gui_layout_add_child(gui, widget.bounds);
    return clicked;
}

gui_slider_float :: (
    gui: *GUI_State, id: string, value: *float32, minimum: float32, maximum: float32,
    position_pixels: V2f, width_pixels: float32, z: float32 = 0
) -> bool {
    full_id := gui_combine_id(gui_last_id(gui), gui_hash_string(id));
    widget := table_find_pointer(*gui.widgets, full_id);
    if !widget {
        table_add(*gui.widgets, full_id, .{});
        widget = table_find_pointer(*gui.widgets, full_id);
    }
    widget.touched = true;
    widget.bounds = .{ position_pixels.x, position_pixels.y, position_pixels.x + width_pixels, position_pixels.y + 18 };
    widget.z = z;

    changed := false;
    if widget.hovered && gui.mouse_left_down && maximum > minimum {
        t := (gui.mouse_position_pixels.x - position_pixels.x) / width_pixels;
        if t < 0 t = 0;
        if t > 1 t = 1;
        next_value := minimum + (maximum - minimum) * t;
        changed = next_value != value.*;
        value.* = next_value;
    }

    fill := ifx maximum > minimum then (value.* - minimum) / (maximum - minimum) else 0.0;
    if fill < 0 fill = 0;
    if fill > 1 fill = 1;
    gui_quad(gui, position_pixels + .{ 0, 7 }, .{ width_pixels, 4 }, .{ 0.06, 0.13, 0.22, 1 }, z);
    gui_quad(gui, position_pixels + .{ 0, 7 }, .{ width_pixels * fill, 4 }, .{ 0.26, 0.68, 1, 1 }, z + 0.01);
    gui_quad(gui, position_pixels + .{ width_pixels * fill - 5, 2 }, .{ 10, 14 }, .{ 0.78, 0.9, 1, 1 }, z + 0.02);
    return changed;
}

gui_slider_float_flow :: (gui: *GUI_State, id: string, value: *float32, minimum: float32, maximum: float32, width_pixels: float32) -> bool {
    changed := gui_slider_float(gui, id, value, minimum, maximum, gui_layout_cursor(gui), width_pixels, gui_layout_z(gui));
    widget := table_find_pointer(*gui.widgets, gui_combine_id(gui_last_id(gui), gui_hash_string(id)));
    gui_layout_add_child(gui, widget.bounds);
    return changed;
}

gui_progress_bar :: (gui: *GUI_State, position_pixels: V2f, width_pixels: float32, progress: float32, z: float32 = 0) -> V4f {
    if progress < 0 progress = 0;
    if progress > 1 progress = 1;
    bounds: V4f = .{ position_pixels.x, position_pixels.y, position_pixels.x + width_pixels, position_pixels.y + 14 };
    gui_quad(gui, position_pixels, .{ width_pixels, 14 }, .{ 0.06, 0.13, 0.22, 1 }, z);
    gui_quad(gui, position_pixels + .{ 2, 2 }, .{ (width_pixels - 4) * progress, 10 }, .{ 0.18, 0.64, 0.92, 1 }, z + 0.01);
    return bounds;
}

gui_progress_bar_flow :: (gui: *GUI_State, width_pixels: float32, progress: float32) -> V4f {
    bounds := gui_progress_bar(gui, gui_layout_cursor(gui), width_pixels, progress, gui_layout_z(gui));
    gui_layout_add_child(gui, bounds);
    return bounds;
}
