// Pure value types and operations. Keep this module dependency-free.

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
