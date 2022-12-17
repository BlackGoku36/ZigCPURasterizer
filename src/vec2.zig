pub const Vec2 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

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
        var len: f32 = a.getLength();
        if (len > 0) {
            var inv: f32 = 1.0 / len;
            a.x = a.x * inv;
            a.y = a.y * inv;
        }
        return a;
    }

    pub fn fromU32(x: u32, y: u32) Vec2 {
        return Vec2{
            .x = @intToFloat(f32, x),
            .y = @intToFloat(f32, y),
        };
    }
};
