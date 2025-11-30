const Vec3 = @import("vec3.zig").Vec3;

pub const Vec4 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 1.0,

    pub fn add(a: Vec4, b: Vec4) Vec4 {
        return Vec4{
            .x = a.x + b.x,
            .y = a.y + b.y,
            .z = a.z + b.z,
            .w = a.w + b.w,
        };
    }

    pub fn sub(a: Vec4, b: Vec4) Vec4 {
        return Vec4{
            .x = a.x - b.x,
            .y = a.y - b.y,
            .z = a.z - b.z,
            .w = a.w - b.w,
        };
    }

    pub fn dot(a: Vec4, b: Vec4) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn toVec3(self: Vec4) Vec3 {
        return Vec3{ .x = self.x, .y = self.y, .z = self.z };
    }

    pub fn clipToNDC(v: Vec4) Vec4 {
        const clipped_a: Vec4 = Vec4{ .x = v.x / v.w, .y = v.y / v.w, .z = v.z / v.w, .w = 1.0 / v.w };
        return clipped_a;
    }

    pub fn ndcToRaster(a: Vec4, width: f32, height: f32) Vec3 {
        var out_vec = Vec3{};
        out_vec.x = (a.x + 1.0) * width * 0.5;
        out_vec.y = (1.0 - a.y) * 0.5 * height;
        out_vec.z = 1.0 / a.z;
        return out_vec;
    }
};
