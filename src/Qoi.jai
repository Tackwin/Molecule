// Quite OK Image (QOI) codec. This module has no platform or allocator dependency.
// Callers provide the input and output storage.

QOI_MAGIC : u32 : 0x716f6966;
QOI_HEADER_BYTES :: 14;
QOI_END_MARKER_BYTES :: 8;

Qoi_Pixel :: struct {
    r: u8;
    g: u8;
    b: u8;
    a: u8 = 255;
}

Qoi_Image_Info :: struct {
    width: u32;
    height: u32;
    channels: u8;
    colorspace: u8;
}

qoi_encoded_max_size :: (pixel_count: u64) -> u64 {
    return QOI_HEADER_BYTES + pixel_count * 5 + QOI_END_MARKER_BYTES;
}

qoi_pixel_hash :: (pixel: Qoi_Pixel) -> u8 {
    hash := cast(u32) pixel.r * 3;
    hash += cast(u32) pixel.g * 5;
    hash += cast(u32) pixel.b * 7;
    hash += cast(u32) pixel.a * 11;
    return cast(u8) (hash % 64);
}

qoi_pixels_equal :: (a: Qoi_Pixel, b: Qoi_Pixel) -> bool {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

qoi_add_delta :: (value: u8, delta: s32) -> u8 {
    result := cast(s32) value + delta;
    if result < 0 {
        result += 256;
    }
    if result >= 256 {
        result -= 256;
    }
    return cast(u8) result;
}

qoi_write_u32_be :: (output: [] u8, cursor: *u64, value: u32) -> bool {
    if cursor.* + 4 > xx output.count {
        return false;
    }
    output[cursor.* + 0] = cast(u8) ((value >> 24) & 0xff);
    output[cursor.* + 1] = cast(u8) ((value >> 16) & 0xff);
    output[cursor.* + 2] = cast(u8) ((value >> 8) & 0xff);
    output[cursor.* + 3] = cast(u8) (value & 0xff);
    cursor.* += 4;
    return true;
}

qoi_read_u32_be :: (input: [] u8, cursor: *u64, value: *u32) -> bool {
    if cursor.* + 4 > xx input.count {
        return false;
    }
    result := cast(u32) input[cursor.* + 0];
    result = result * 256 + input[cursor.* + 1];
    result = result * 256 + input[cursor.* + 2];
    result = result * 256 + input[cursor.* + 3];
    value.* = result;
    cursor.* += 4;
    return true;
}

qoi_write_byte :: (output: [] u8, cursor: *u64, value: u8) -> bool {
    if cursor.* >= xx output.count {
        return false;
    }
    output[cursor.*] = value;
    cursor.* += 1;
    return true;
}

qoi_encode :: (
    info: Qoi_Image_Info,
    pixels: [] Qoi_Pixel,
    output: [] u8
) -> byte_count: u64, success: bool {
    if info.width == 0 || info.height == 0 {
        return 0, false;
    }
    if info.channels != 3 && info.channels != 4 {
        return 0, false;
    }
    pixel_count := cast(u64) info.width * info.height;
    if pixel_count != xx pixels.count {
        return 0, false;
    }
    if xx output.count < qoi_encoded_max_size(pixel_count) {
        return 0, false;
    }

    cursor: u64 = 0;
    if !qoi_write_u32_be(output, *cursor, QOI_MAGIC) {
        return 0, false;
    }
    if !qoi_write_u32_be(output, *cursor, info.width) {
        return 0, false;
    }
    if !qoi_write_u32_be(output, *cursor, info.height) {
        return 0, false;
    }
    if !qoi_write_byte(output, *cursor, info.channels) {
        return 0, false;
    }
    if !qoi_write_byte(output, *cursor, info.colorspace) {
        return 0, false;
    }

    index: [64] Qoi_Pixel;
    for 0..63 {
        index[it] = .{ 0, 0, 0, 0 };
    }
    previous: Qoi_Pixel = .{ 0, 0, 0, 255 };
    run: u8 = 0;
    for pixels {
        pixel := it;
        if qoi_pixels_equal(pixel, previous) {
            run += 1;
            if run == 62 {
                if !qoi_write_byte(output, *cursor, 0xc0 | (run - 1)) {
                    return 0, false;
                }
                run = 0;
            }
            continue;
        }

        if run > 0 {
            if !qoi_write_byte(output, *cursor, 0xc0 | (run - 1)) {
                return 0, false;
            }
            run = 0;
        }

        index_slot := qoi_pixel_hash(pixel);
        if qoi_pixels_equal(index[index_slot], pixel) {
            if !qoi_write_byte(output, *cursor, index_slot) {
                return 0, false;
            }
        } else {
            index[index_slot] = pixel;
            if pixel.a == previous.a {
                vr := cast(s32) pixel.r - previous.r;
                vg := cast(s32) pixel.g - previous.g;
                vb := cast(s32) pixel.b - previous.b;
                if vr >= -2 && vr <= 1 && vg >= -2 && vg <= 1 && vb >= -2 && vb <= 1 {
                    chunk := 0x40 | cast(u8) (vr + 2) << 4 | cast(u8) (vg + 2) << 2 | cast(u8) (vb + 2);
                    if !qoi_write_byte(output, *cursor, chunk) {
                        return 0, false;
                    }
                } else {
                    vg_r := vr - vg;
                    vg_b := vb - vg;
                    if vg >= -32 && vg <= 31 && vg_r >= -8 && vg_r <= 7 && vg_b >= -8 && vg_b <= 7 {
                        if !qoi_write_byte(output, *cursor, 0x80 | cast(u8) (vg + 32)) {
                            return 0, false;
                        }
                        if !qoi_write_byte(output, *cursor, cast(u8) (vg_r + 8) << 4 | cast(u8) (vg_b + 8)) {
                            return 0, false;
                        }
                    } else {
                        if !qoi_write_byte(output, *cursor, 0xfe) {
                            return 0, false;
                        }
                        if !qoi_write_byte(output, *cursor, pixel.r) {
                            return 0, false;
                        }
                        if !qoi_write_byte(output, *cursor, pixel.g) {
                            return 0, false;
                        }
                        if !qoi_write_byte(output, *cursor, pixel.b) {
                            return 0, false;
                        }
                    }
                }
            } else {
                if !qoi_write_byte(output, *cursor, 0xff) {
                    return 0, false;
                }
                if !qoi_write_byte(output, *cursor, pixel.r) {
                    return 0, false;
                }
                if !qoi_write_byte(output, *cursor, pixel.g) {
                    return 0, false;
                }
                if !qoi_write_byte(output, *cursor, pixel.b) {
                    return 0, false;
                }
                if !qoi_write_byte(output, *cursor, pixel.a) {
                    return 0, false;
                }
            }
        }
        previous = pixel;
    }

    if run > 0 {
        if !qoi_write_byte(output, *cursor, 0xc0 | (run - 1)) {
            return 0, false;
        }
    }
    for 0..6 {
        if !qoi_write_byte(output, *cursor, 0) {
            return 0, false;
        }
    }
    if !qoi_write_byte(output, *cursor, 1) {
        return 0, false;
    }
    return cursor, true;
}

qoi_decode :: (
    input: [] u8,
    pixels: [] Qoi_Pixel
) -> Qoi_Image_Info, bool {
    info: Qoi_Image_Info;
    cursor: u64 = 0;
    magic: u32;
    if !qoi_read_u32_be(input, *cursor, *magic) {
        return .{}, false;
    }
    if magic != QOI_MAGIC {
        return .{}, false;
    }
    if !qoi_read_u32_be(input, *cursor, *info.width) {
        return .{}, false;
    }
    if !qoi_read_u32_be(input, *cursor, *info.height) {
        return .{}, false;
    }
    if cursor + 2 > xx input.count {
        return .{}, false;
    }
    info.channels = input[cursor + 0];
    info.colorspace = input[cursor + 1];
    cursor += 2;
    if info.width == 0 || info.height == 0 {
        return .{}, false;
    }
    if info.channels != 3 && info.channels != 4 {
        return .{}, false;
    }
    pixel_count := cast(u64) info.width * info.height;
    if pixel_count != xx pixels.count {
        return .{}, false;
    }

    index: [64] Qoi_Pixel;
    for 0..63 {
        index[it] = .{ 0, 0, 0, 0 };
    }
    previous: Qoi_Pixel = .{ 0, 0, 0, 255 };
    run: u8 = 0;
    for 0..pixel_count - 1 {
        if run > 0 {
            run -= 1;
        } else {
            if cursor >= xx input.count {
                return .{}, false;
            }
            chunk := input[cursor];
            cursor += 1;
            if chunk == 0xfe {
                if cursor + 3 > xx input.count {
                    return .{}, false;
                }
                previous.r = input[cursor + 0];
                previous.g = input[cursor + 1];
                previous.b = input[cursor + 2];
                cursor += 3;
            } else if chunk == 0xff {
                if cursor + 4 > xx input.count {
                    return .{}, false;
                }
                previous.r = input[cursor + 0];
                previous.g = input[cursor + 1];
                previous.b = input[cursor + 2];
                previous.a = input[cursor + 3];
                cursor += 4;
            } else if (chunk & 0xc0) == 0x00 {
                previous = index[chunk];
            } else if (chunk & 0xc0) == 0x40 {
                previous.r = qoi_add_delta(previous.r, cast(s32) (chunk >> 4 & 0x03) - 2);
                previous.g = qoi_add_delta(previous.g, cast(s32) (chunk >> 2 & 0x03) - 2);
                previous.b = qoi_add_delta(previous.b, cast(s32) (chunk & 0x03) - 2);
            } else if (chunk & 0xc0) == 0x80 {
                if cursor >= xx input.count {
                    return .{}, false;
                }
                second := input[cursor];
                cursor += 1;
                vg := cast(s32) (chunk & 0x3f) - 32;
                previous.r = qoi_add_delta(previous.r, vg - 8 + (second >> 4 & 0x0f));
                previous.g = qoi_add_delta(previous.g, vg);
                previous.b = qoi_add_delta(previous.b, vg - 8 + (second & 0x0f));
            } else {
                run = chunk & 0x3f;
            }
        }
        index[qoi_pixel_hash(previous)] = previous;
        pixels[it] = previous;
    }

    if cursor + QOI_END_MARKER_BYTES != xx input.count {
        return .{}, false;
    }
    for 0..6 {
        if input[cursor + xx it] != 0 {
            return .{}, false;
        }
    }
    if input[cursor + 7] != 1 {
        return .{}, false;
    }
    return info, true;
}
