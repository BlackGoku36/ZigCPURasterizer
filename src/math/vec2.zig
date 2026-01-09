const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub fn init(v: f32) Vec2 {
        return Vec2{
            .x = v,
            .y = v,
        };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return Vec2{
            .x = a.x + b.x,
            .y = a.y + b.y,
        };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return Vec2{
            .x = a.x - b.x,
            .y = a.y - b.y,
        };
    }

    pub fn multv(a: Vec2, b: Vec2) Vec2 {
        return Vec2{
            .x = a.x * b.x,
            .y = a.y * b.y,
        };
    }

    pub fn multf(a: Vec2, s: f32) Vec2 {
        return Vec2{
            .x = a.x * s,
            .y = a.y * s,
        };
    }

    pub fn dot(a: Vec2, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn getLength(a: Vec2) f32 {
        return @sqrt(a.x * a.x + a.y * a.y);
    }

    pub fn normalize(a: Vec2) Vec2 {
        const len: f32 = a.getLength();
        if (len > 0) {
            const inv: f32 = 1.0 / len;
            a.x = a.x * inv;
            a.y = a.y * inv;
        }
        return a;
    }

    pub fn clamp(value: Vec2, lower: Vec2, upper: Vec2) Vec2 {
        return Vec2{
            .x = std.math.clamp(value.x, lower.x, upper.x),
            .y = std.math.clamp(value.y, lower.y, upper.y),
        };
    }

    pub fn fromU32(x: u32, y: u32) Vec2 {
        return Vec2{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
        };
    }

    pub fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
        return Vec2{
            .x = std.math.lerp(a.x, b.x, t),
            .y = std.math.lerp(a.y, b.y, t),
        };
    }
};
