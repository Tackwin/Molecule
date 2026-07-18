#import "Basic";
#import "Qoi";

main :: () {
    source: [8] Qoi_Pixel = .[
        .{ 0, 0, 0, 255 },
        .{ 255, 0, 0, 255 },
        .{ 255, 0, 0, 255 },
        .{ 4, 2, 1, 255 },
        .{ 3, 1, 0, 255 },
        .{ 3, 1, 0, 80 },
        .{ 3, 1, 0, 80 },
        .{ 255, 255, 255, 255 },
    ];
    encoded_storage: [QOI_HEADER_BYTES + 8 * 5 + QOI_END_MARKER_BYTES] u8;
    info: Qoi_Image_Info = .{ width = 4, height = 2, channels = 4, colorspace = 0 };
    encoded_count, encoded := qoi_encode(info, source, encoded_storage);
    if !encoded {
        print("QOI encode failed.\n");
        return;
    }
    decoded: [8] Qoi_Pixel;
    decoded_info, decoded_ok := qoi_decode(
        .{ data = *encoded_storage[0], count = xx encoded_count },
        decoded
    );
    if !decoded_ok || decoded_info.width != info.width || decoded_info.height != info.height {
        print("QOI decode failed.\n");
        return;
    }
    for 0..7 {
        if !qoi_pixels_equal(source[it], decoded[it]) {
            print("QOI round-trip mismatch.\n");
            return;
        }
    }
    print("QOI round-trip passed.\n");
}
