const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;

pub const Vec4 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 1.0,

    pub fn init(a: f32) Vec4 {
        return Vec4{
            .x = a,
            .y = a,
            .z = a,
            .w = a,
        };
    }

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

    pub fn multf(a: Vec4, s: f32) Vec4 {
        return Vec4{
            .x = a.x * s,
            .y = a.y * s,
            .z = a.z * s,
            .w = a.w * s,
        };
    }

    pub fn divv(a: Vec4, b: Vec4) Vec4 {
        return Vec4{
            .x = a.x / b.x,
            .y = a.y / b.y,
            .z = a.z / b.z,
            .w = a.w / b.w,
        };
    }

    pub fn dot(a: Vec4, b: Vec4) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn mix(start: Vec4, end: Vec4, t: f32) Vec4 {
        return Vec4{
            .x = start.x * (1 - t) + end.x * t,
            .y = start.y * (1 - t) + end.y * t,
            .z = start.z * (1 - t) + end.z * t,
            .w = start.w * (1 - t) + end.w * t,
        };
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

    pub fn lerp(a: Vec4, b: Vec4, t: f32) Vec4 {
        return Vec4{
            .x = std.math.lerp(a.x, b.x, t),
            .y = std.math.lerp(a.y, b.y, t),
            .z = std.math.lerp(a.z, b.z, t),
            .w = std.math.lerp(a.w, b.w, t),
        };
    }
};
