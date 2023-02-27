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
};
