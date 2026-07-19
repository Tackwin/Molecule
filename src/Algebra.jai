// Pure value types and operations.

#import "Math";

V2i :: struct {
    x: s32;
    y: s32;
}

V2f :: struct {
    x: float32;
    y: float32;
}

V3f :: struct {
    x: float32;
    y: float32;
    z: float32;
}

V4f :: struct {
    x: float32;
    y: float32;
    z: float32;
    w: float32;
}

M4f :: struct {
    // Column-major storage. Matrices transform column vectors on the left: result = matrix * vector.
    elements: [16] float32;
}

operator + :: (a: V2i, b: V2i) -> V2i { return .{ a.x + b.x, a.y + b.y }; }
operator - :: (a: V2i, b: V2i) -> V2i { return .{ a.x - b.x, a.y - b.y }; }
operator * :: (a: V2i, scale: s32) -> V2i #symmetric { return .{ a.x * scale, a.y * scale }; }
operator / :: (a: V2i, scale: s32) -> V2i { return .{ a.x / scale, a.y / scale }; }
operator == :: (a: V2i, b: V2i) -> bool { return a.x == b.x && a.y == b.y; }

operator + :: (a: V2f, b: V2f) -> V2f { return .{ a.x + b.x, a.y + b.y }; }
operator - :: (a: V2f, b: V2f) -> V2f { return .{ a.x - b.x, a.y - b.y }; }
operator * :: (a: V2f, scale: float32) -> V2f #symmetric { return .{ a.x * scale, a.y * scale }; }
operator / :: (a: V2f, scale: float32) -> V2f { return .{ a.x / scale, a.y / scale }; }
operator == :: (a: V2f, b: V2f) -> bool { return a.x == b.x && a.y == b.y; }
dot :: (a: V2f, b: V2f) -> float32 { return a.x * b.x + a.y * b.y; }

operator + :: (a: V3f, b: V3f) -> V3f { return .{ a.x + b.x, a.y + b.y, a.z + b.z }; }
operator - :: (a: V3f, b: V3f) -> V3f { return .{ a.x - b.x, a.y - b.y, a.z - b.z }; }
operator * :: (a: V3f, scale: float32) -> V3f #symmetric { return .{ a.x * scale, a.y * scale, a.z * scale }; }
operator / :: (a: V3f, scale: float32) -> V3f { return .{ a.x / scale, a.y / scale, a.z / scale }; }
operator == :: (a: V3f, b: V3f) -> bool { return a.x == b.x && a.y == b.y && a.z == b.z; }
dot :: (a: V3f, b: V3f) -> float32 { return a.x * b.x + a.y * b.y + a.z * b.z; }

cross :: (a: V3f, b: V3f) -> V3f {
    return .{
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    };
}

length :: (value: V3f) -> float32 { return sqrt(dot(value, value)); }

normalize :: (value: V3f) -> V3f {
    value_length := length(value);
    if value_length == 0 return .{};
    return value / value_length;
}

m4_identity :: () -> M4f {
    result: M4f = .{};
    result.elements[0] = 1;
    result.elements[5] = 1;
    result.elements[10] = 1;
    result.elements[15] = 1;
    return result;
}

m4_translation :: (translation: V3f) -> M4f {
    result := m4_identity();
    result.elements[12] = translation.x;
    result.elements[13] = translation.y;
    result.elements[14] = translation.z;
    return result;
}

m4_scale :: (scale: V3f) -> M4f {
    result: M4f = .{};
    result.elements[0] = scale.x;
    result.elements[5] = scale.y;
    result.elements[10] = scale.z;
    result.elements[15] = 1;
    return result;
}

operator * :: (a: M4f, b: M4f) -> M4f {
    result: M4f = .{};
    for column: 0..3 {
        for row: 0..3 {
            result.elements[column * 4 + row] =
                a.elements[0 * 4 + row] * b.elements[column * 4 + 0] +
                a.elements[1 * 4 + row] * b.elements[column * 4 + 1] +
                a.elements[2 * 4 + row] * b.elements[column * 4 + 2] +
                a.elements[3 * 4 + row] * b.elements[column * 4 + 3];
        }
    }
    return result;
}

m4_look_at :: (position: V3f, target: V3f, up: V3f) -> M4f {
    forward := normalize(target - position);
    right := normalize(cross(forward, up));
    corrected_up := cross(right, forward);
    result := m4_identity();
    result.elements[0] = right.x;
    result.elements[1] = corrected_up.x;
    result.elements[2] = -forward.x;
    result.elements[4] = right.y;
    result.elements[5] = corrected_up.y;
    result.elements[6] = -forward.y;
    result.elements[8] = right.z;
    result.elements[9] = corrected_up.z;
    result.elements[10] = -forward.z;
    result.elements[12] = -dot(right, position);
    result.elements[13] = -dot(corrected_up, position);
    result.elements[14] = dot(forward, position);
    return result;
}

m4_perspective :: (focal_length: float32, aspect_ratio: float32, near_plane: float32, far_plane: float32) -> M4f {
    result: M4f = .{};
    result.elements[0] = focal_length / aspect_ratio;
    result.elements[5] = focal_length;
    result.elements[10] = far_plane / (near_plane - far_plane);
    result.elements[11] = -1;
    result.elements[14] = (far_plane * near_plane) / (near_plane - far_plane);
    return result;
}
